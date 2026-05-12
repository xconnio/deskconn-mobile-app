import 'package:deskconn_mobile_app/core/wamp/desktop_connection_manager.dart';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:deskconn_mobile_app/core/file_explorer/file_explorer_controller.dart';
import 'package:deskconn_mobile_app/core/file_explorer/models.dart';
import 'package:deskconn_mobile_app/core/shell/shell_background_service.dart';

class FileExplorerScreen extends StatefulWidget {
  final ShellLaunchConfig config;

  const FileExplorerScreen({super.key, required this.config});

  @override
  State<FileExplorerScreen> createState() => _FileExplorerScreenState();
}

class _FileExplorerScreenState extends State<FileExplorerScreen> {
  FileExplorerController? _controller;
  FileBrowseResult? _currentBrowse;
  bool _isLoading = true;
  String? _error;
  bool _showHidden = false;

  // Cache for directory listings to make back navigation instant
  static final Map<String, FileBrowseResult> _browseCache = {};

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    if (!mounted) return;

    // Fast path: session already established by DesktopDetailsScreen — no async needed
    final existing = DesktopConnectionManager().get(widget.config.realm);
    if (existing != null) {
      _controller = FileExplorerController.getOrCreate(existing.session, widget.config.realm);
      // If controller is reused (key exchange already done), skip the loading state entirely
      if (_controller!.isKeyExchanged) {
        await _loadPath(_currentBrowse?.path ?? '');
        return;
      }
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final connection =
          existing ??
          await DesktopConnectionManager().connect(
            realm: widget.config.realm,
            authId: widget.config.authId,
            privateKey: widget.config.privateKey,
            webRtcEnabled: widget.config.webRtcEnabled,
            turnCredentials: widget.config.turnCredentials,
          );
      _controller = FileExplorerController.getOrCreate(connection.session, widget.config.realm);
      await _loadPath('');
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  // Force-release and reconnect — used by Reconnect button and auto-reconnect
  Future<void> _reconnect() async {
    FileExplorerController.invalidate(widget.config.realm);
    await DesktopConnectionManager().release(widget.config.realm);
    _controller = null;
    await _initialize();
  }

  Future<void> _loadPath(String path) async {
    if (_controller == null) return;

    final cacheKey = '${widget.config.realm}:$path';
    if (_browseCache.containsKey(cacheKey)) {
      setState(() {
        _currentBrowse = _browseCache[cacheKey];
        _isLoading = false;
      });
      _refreshPath(path);
      return;
    }

    setState(() => _isLoading = true);
    await _refreshPath(path);
  }

  Future<void> _refreshPath(String path) async {
    try {
      final result = await _controller!.browse(path);
      final cacheKey = '${widget.config.realm}:$path';
      _browseCache[cacheKey] = result;
      if (mounted) {
        setState(() {
          _currentBrowse = result;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      final sessionAlive = _controller?.session.isConnected() ?? false;
      if (!sessionAlive) {
        await _reconnect();
        return;
      }
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _onEntryTap(FileEntry entry) {
    if (entry.isDir) {
      final newPath = _currentBrowse!.path == '/' ? '/${entry.name}' : '${_currentBrowse!.path}/${entry.name}';
      _loadPath(newPath);
    } else {
      final path = _currentBrowse!.path == '/' ? '/${entry.name}' : '${_currentBrowse!.path}/${entry.name}';
      Navigator.push(
        context,
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) =>
              FilePreviewScreen(controller: _controller!, entry: entry, path: path),
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
        ),
      );
    }
  }

  void _goUp() {
    if (_currentBrowse == null ||
        _currentBrowse!.path == _currentBrowse!.homePath ||
        _currentBrowse!.path == '/' ||
        _currentBrowse!.path.isEmpty) {
      return;
    }
    final parts = _currentBrowse!.path.split('/');
    parts.removeLast();
    final parentPath = parts.join('/');
    _loadPath(parentPath.isEmpty ? '/' : parentPath);
  }

  @override
  Widget build(BuildContext context) {
    final isAtRoot =
        _currentBrowse == null ||
        _currentBrowse!.path == _currentBrowse!.homePath ||
        _currentBrowse!.path == '/' ||
        _currentBrowse!.path.isEmpty;

    return PopScope(
      canPop: isAtRoot,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _goUp();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('File Explorer'),
          actions: [
            IconButton(
              icon: Icon(_showHidden ? Icons.visibility : Icons.visibility_off),
              onPressed: () => setState(() => _showHidden = !_showHidden),
              tooltip: 'Show hidden files',
            ),
            IconButton(icon: const Icon(Icons.refresh), onPressed: () => _loadPath(_currentBrowse?.path ?? '')),
          ],
        ),
        body: Column(
          children: [
            if (_currentBrowse != null) _Breadcrumbs(path: _currentBrowse!.path, onPathTap: _loadPath, onUpTap: _goUp),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading && _currentBrowse == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null && _currentBrowse == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Error: $_error'),
            ElevatedButton(onPressed: _reconnect, child: const Text('Reconnect')),
          ],
        ),
      );
    }

    final entries =
        _currentBrowse?.entries.where((e) {
          if (!_showHidden && e.name.startsWith('.')) return false;
          return true;
        }).toList() ??
        [];

    if (entries.isEmpty) {
      return const Center(child: Text('No files found'));
    }

    return ListView.builder(
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        return _FileEntryTile(
          controller: _controller!,
          parentPath: _currentBrowse!.path,
          entry: entry,
          onTap: () => _onEntryTap(entry),
          onLongPress: () => _showEntryOptions(entry),
        );
      },
    );
  }

  void _showEntryOptions(FileEntry entry) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('Properties'),
              onTap: () {
                Navigator.pop(context);
                _showProperties(entry);
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Rename'),
              onTap: () {
                Navigator.pop(context);
                _showRenameDialog(entry);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('Delete', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                _showDeleteConfirmation(entry);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showProperties(FileEntry entry) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(entry.name),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Type: ${entry.isDir ? 'Directory' : 'File'}'),
            Text('Size: ${formatSize(entry.size)}'),
            Text('Modified: ${DateTime.fromMillisecondsSinceEpoch(entry.mtime * 1000)}'),
            Text('Permissions: ${entry.mode.toRadixString(8)}'),
            if (entry.isSymlink) Text('Symlink target: ${entry.symlinkTarget}'),
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
      ),
    );
  }

  void _showRenameDialog(FileEntry entry) {
    final controller = TextEditingController(text: entry.name);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'New name'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              final newName = controller.text.trim();
              if (newName.isNotEmpty && newName != entry.name) {
                Navigator.pop(context);
                try {
                  final oldPath = '${_currentBrowse!.path}/${entry.name}';
                  final newPath = '${_currentBrowse!.path}/$newName';
                  await _controller!.rename(oldPath, newPath);
                  _loadPath(_currentBrowse!.path);
                } catch (e) {
                  _showErrorSnackBar('Rename failed: $e');
                }
              }
            },
            child: const Text('Rename'),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirmation(FileEntry entry) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete'),
        content: Text('Are you sure you want to delete ${entry.name}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                final path = '${_currentBrowse!.path}/${entry.name}';
                await _controller!.delete(path);
                _loadPath(_currentBrowse!.path);
              } catch (e) {
                _showErrorSnackBar('Delete failed: $e');
              }
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}

String formatSize(int bytes) {
  if (bytes <= 0) return "0 B";
  const suffixes = ["B", "KB", "MB", "GB", "TB"];
  var i = (math.log(bytes) / math.log(1024)).floor();
  return "${(bytes / math.pow(1024, i)).toStringAsFixed(2)} ${suffixes[i]}";
}

class _Breadcrumbs extends StatelessWidget {
  final String path;
  final Function(String) onPathTap;
  final VoidCallback onUpTap;

  const _Breadcrumbs({required this.path, required this.onPathTap, required this.onUpTap});

  @override
  Widget build(BuildContext context) {
    final parts = path == '/' ? [''] : path.split('/');
    if (parts.isEmpty) parts.add('');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      color: Theme.of(context).cardColor,
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_upward),
            onPressed: onUpTap,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              reverse: true,
              child: Row(
                children: [
                  for (var i = 0; i < parts.length; i++) ...[
                    if (i > 0) const Icon(Icons.chevron_right, size: 16),
                    TextButton(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: () {
                        final targetPath = parts.sublist(0, i + 1).join('/');
                        onPathTap(targetPath.isEmpty ? '/' : targetPath);
                      },
                      child: Text(parts[i].isEmpty ? 'Root' : parts[i]),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class FilePreviewScreen extends StatefulWidget {
  final FileExplorerController controller;
  final FileEntry entry;
  final String path;

  const FilePreviewScreen({super.key, required this.controller, required this.entry, required this.path});

  @override
  State<FilePreviewScreen> createState() => _FilePreviewScreenState();
}

class _FilePreviewScreenState extends State<FilePreviewScreen> {
  late Future<Uint8List> _contentFuture;

  @override
  void initState() {
    super.initState();
    _contentFuture = widget.controller.read(widget.path);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF272822), // Sublime-like dark background
      appBar: AppBar(
        title: Text(widget.entry.name),
        backgroundColor: const Color(0xFF1E1E1E),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: () {
              // TODO: Implement download
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Download not implemented yet')));
            },
          ),
        ],
      ),
      body: FutureBuilder<Uint8List>(
        future: _contentFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Colors.white));
          }

          if (snapshot.hasError) {
            return Center(
              child: Text('Error: ${snapshot.error}', style: const TextStyle(color: Colors.red)),
            );
          }

          if (!snapshot.hasData) {
            return const Center(
              child: Text('No data', style: TextStyle(color: Colors.white)),
            );
          }

          final data = snapshot.data!;
          final ext = widget.entry.name.split('.').last.toLowerCase();

          if (['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(ext)) {
            return Center(child: Image.memory(data));
          }

          // Added .sh and other common code extensions
          if ([
            'txt',
            'md',
            'json',
            'yaml',
            'xml',
            'log',
            'sh',
            'py',
            'js',
            'ts',
            'c',
            'cpp',
            'h',
            'css',
            'html',
          ].contains(ext)) {
            try {
              final text = utf8.decode(data);
              return SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: SelectableText(
                  text,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    color: Color(0xFFF8F8F2), // Sublime-like text color
                    fontSize: 14,
                  ),
                ),
              );
            } catch (e) {
              return const Center(
                child: Text('Cannot display binary file as text', style: TextStyle(color: Colors.white)),
              );
            }
          }

          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  ext == 'pdf' ? Icons.picture_as_pdf : Icons.insert_drive_file,
                  size: 64,
                  color: ext == 'pdf' ? Colors.red : Colors.grey,
                ),
                const SizedBox(height: 16),
                Text(
                  ext == 'pdf' ? 'PDF Preview not supported yet' : 'No preview available for .$ext',
                  style: const TextStyle(color: Colors.white),
                ),
                const SizedBox(height: 16),
                Text('Size: ${formatSize(widget.entry.size)}', style: const TextStyle(color: Colors.grey)),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _FileEntryTile extends StatelessWidget {
  final FileExplorerController controller;
  final String parentPath;
  final FileEntry entry;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _FileEntryTile({
    required this.controller,
    required this.parentPath,
    required this.entry,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final ext = entry.name.split('.').last.toLowerCase();
    final isImage = ['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(ext);

    return ListTile(
      leading: SizedBox(
        width: 40,
        height: 40,
        child: isImage
            ? FutureBuilder<Uint8List>(
                future: controller.thumbnail(parentPath == '/' ? '/${entry.name}' : '$parentPath/${entry.name}'),
                builder: (context, snapshot) {
                  if (snapshot.hasData) {
                    return Image.memory(snapshot.data!, fit: BoxFit.cover);
                  }
                  if (snapshot.hasError) {
                    return Icon(Icons.image_not_supported, color: Colors.grey[400], size: 20);
                  }
                  return Icon(Icons.image, color: Colors.grey[400]);
                },
              )
            : Icon(entry.isDir ? Icons.folder : _getFileIcon(entry.name), color: entry.isDir ? Colors.amber : null),
      ),
      title: Text(entry.name),
      subtitle: entry.isDir ? null : Text(formatSize(entry.size)),
      onTap: onTap,
      onLongPress: onLongPress,
      trailing: IconButton(icon: const Icon(Icons.more_vert), onPressed: onLongPress),
    );
  }

  IconData _getFileIcon(String name) {
    final ext = name.split('.').last.toLowerCase();
    switch (ext) {
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'webp':
        return Icons.image;
      case 'mp4':
      case 'mkv':
      case 'webm':
        return Icons.movie;
      case 'mp3':
      case 'wav':
      case 'ogg':
      case 'flac':
        return Icons.audiotrack;
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'zip':
      case 'rar':
      case '7z':
      case 'tar':
      case 'gz':
        return Icons.archive;
      case 'txt':
      case 'md':
      case 'json':
      case 'yaml':
        return Icons.description;
      default:
        return Icons.insert_drive_file;
    }
  }
}
