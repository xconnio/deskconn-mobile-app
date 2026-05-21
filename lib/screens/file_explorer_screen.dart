import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:pdfx/pdfx.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:deskconn_mobile_app/core/wamp/desktop_connection_manager.dart';
import 'package:deskconn_mobile_app/core/file_explorer/file_explorer_controller.dart';
import 'package:deskconn_mobile_app/core/file_explorer/models.dart';
import 'package:deskconn_mobile_app/core/terminal/terminal_background_service.dart';
import 'package:deskconn_mobile_app/theme/colors.dart';

const _kImageExts = {'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'ico'};
const _kTextExts = {
  'txt',
  'md',
  'json',
  'yaml',
  'yml',
  'xml',
  'log',
  'sh',
  'bash',
  'zsh',
  'fish',
  'py',
  'js',
  'ts',
  'jsx',
  'tsx',
  'c',
  'cpp',
  'h',
  'hpp',
  'cc',
  'css',
  'html',
  'htm',
  'dart',
  'go',
  'rs',
  'rb',
  'java',
  'kt',
  'swift',
  'cs',
  'php',
  'sql',
  'r',
  'toml',
  'ini',
  'cfg',
  'conf',
  'env',
  'properties',
  'gradle',
  'cmake',
  'makefile',
  'dockerfile',
};
const _kVideoExts = {'mp4', 'mkv', 'avi', 'mov', 'webm', 'flv', 'm4v', 'wmv', '3gp'};
const _kAudioExts = {'mp3', 'wav', 'ogg', 'flac', 'aac', 'm4a', 'wma', 'opus'};

class FileExplorerScreen extends StatefulWidget {
  final DesktopSessionLaunchConfig config;

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

  FileEntry? _clipboardEntry;
  bool _clipboardIsCut = false;

  static final Map<String, FileBrowseResult> _browseCache = {};

  void _log(String message) {
    debugPrint('[FileExplorer ${widget.config.realm} ${DateTime.now().toIso8601String()}] $message');
  }

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    if (!mounted) return;
    _log('initialize');

    final existing = DesktopConnectionManager().get(widget.config.realm);
    if (existing != null) {
      _log('reusing cached desktop session');
      _controller = FileExplorerController(existing.session, widget.config.realm);
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
          await DesktopConnectionManager().acquire(
            realm: widget.config.realm,
            authId: widget.config.authId,
            privateKey: widget.config.privateKey,
            webRtcEnabled: widget.config.webRtcEnabled,
            turnCredentials: widget.config.turnCredentials,
          );
      _log('controller ready p2p=${connection.isP2P}');
      _controller = FileExplorerController(connection.session, widget.config.realm);
      await _loadPath('');
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
      _log('initialize failed error=$e');
    }
  }

  Future<void> _reconnect() async {
    _log('reconnect');
    await DesktopConnectionManager().release(widget.config.realm);
    _controller = null;
    await _initialize();
  }

  Future<void> _loadPath(String path) async {
    if (_controller == null) return;

    final cacheKey = '${widget.config.realm}:$path';
    if (_browseCache.containsKey(cacheKey)) {
      _log('browse cache hit path=$path');
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
      _log('browse path=$path');
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
        _log('session lost during browse path=$path');
        await _reconnect();
        return;
      }
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
      _log('browse failed path=$path error=$e');
    }
  }

  String _fullPath(FileEntry entry) {
    if (entry.path.isNotEmpty) return entry.path;
    final dir = _currentBrowse!.path;
    return dir == '/' ? '/${entry.name}' : '$dir/${entry.name}';
  }

  String? _resolveSymlinkTarget(FileEntry entry) {
    final target = entry.symlinkTarget;
    if (target == null || target.isEmpty) return null;
    if (target.startsWith('/')) return target;
    final lastSlash = entry.path.lastIndexOf('/');
    final parentDir = lastSlash > 0 ? entry.path.substring(0, lastSlash) : '/';
    final parts = '$parentDir/$target'.split('/');
    final resolved = <String>[];
    for (final part in parts) {
      if (part == '..' && resolved.isNotEmpty) {
        resolved.removeLast();
      } else if (part != '.' && part.isNotEmpty) {
        resolved.add(part);
      }
    }
    return '/${resolved.join('/')}';
  }

  Future<void> _openSymlink(FileEntry entry) async {
    final resolved = _resolveSymlinkTarget(entry);
    final browsePath = resolved ?? _fullPath(entry);

    final prevBrowse = _currentBrowse;
    setState(() => _isLoading = true);

    try {
      final result = await _controller!.browse(browsePath);
      _browseCache['${widget.config.realm}:$browsePath'] = result;
      if (mounted) {
        setState(() {
          _currentBrowse = result;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _currentBrowse = prevBrowse;
        _isLoading = false;
      });
      Navigator.push(
        context,
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) =>
              FilePreviewScreen(controller: _controller!, entry: entry, path: browsePath),
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
        ),
      );
    }
  }

  void _onEntryTap(FileEntry entry) {
    if (entry.isDir) {
      _loadPath(_fullPath(entry));
    } else if (entry.isSymlink) {
      _openSymlink(entry);
    } else {
      Navigator.push(
        context,
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) =>
              FilePreviewScreen(controller: _controller!, entry: entry, path: _fullPath(entry)),
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
            if (_clipboardEntry != null) _buildClipboardBanner(),
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
          entry: entry,
          onTap: () => _onEntryTap(entry),
          onLongPress: () => _showEntryOptions(entry),
        );
      },
    );
  }

  Widget _buildClipboardBanner() {
    return ColoredBox(
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Row(
          children: [
            Icon(_clipboardIsCut ? Icons.content_cut : Icons.content_copy, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${_clipboardIsCut ? 'Cut' : 'Copied'}: ${_clipboardEntry!.name}',
                style: const TextStyle(fontSize: 13),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            TextButton(onPressed: _pasteHere, child: const Text('Paste here')),
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              onPressed: () => setState(() {
                _clipboardEntry = null;
                _clipboardIsCut = false;
              }),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pasteHere() async {
    if (_clipboardEntry == null || _currentBrowse == null) return;
    final entry = _clipboardEntry!;
    final isCut = _clipboardIsCut;
    final srcPath = entry.path;
    final srcDir = srcPath.substring(0, srcPath.lastIndexOf('/'));
    final destDir = _currentBrowse!.path;
    var destPath = '$destDir/${entry.name}';

    if (destPath == srcPath) {
      if (isCut) {
        setState(() {
          _clipboardEntry = null;
          _clipboardIsCut = false;
        });
        return;
      }
      final name = entry.name;
      final dot = entry.isDir ? -1 : name.lastIndexOf('.');
      destPath = dot > 0 ? '$destDir/${name.substring(0, dot)}_copy${name.substring(dot)}' : '$destDir/${name}_copy';
    }

    try {
      if (isCut) {
        await _controller!.rename(srcPath, destPath);
        _invalidateCacheFor(srcDir);
      } else {
        await _controller!.copy(srcPath, destPath);
      }
      setState(() {
        _clipboardEntry = null;
        _clipboardIsCut = false;
      });
      _invalidateCacheFor(destDir);
      _loadPath(destDir);
    } catch (e) {
      _showErrorSnackBar('Paste failed: $e');
    }
  }

  void _invalidateCacheFor(String path) {
    _browseCache.remove('${widget.config.realm}:$path');
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
              leading: const Icon(Icons.content_copy),
              title: const Text('Copy'),
              onTap: () {
                Navigator.pop(context);
                setState(() {
                  _clipboardEntry = entry;
                  _clipboardIsCut = false;
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('"${entry.name}" copied — navigate to destination and tap Paste here')),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.content_cut),
              title: const Text('Cut'),
              onTap: () {
                Navigator.pop(context);
                setState(() {
                  _clipboardEntry = entry;
                  _clipboardIsCut = true;
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('"${entry.name}" cut — navigate to destination and tap Paste here')),
                );
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
    final location = entry.path.isNotEmpty
        ? entry.path.substring(0, entry.path.lastIndexOf('/'))
        : _currentBrowse?.path ?? '';

    String type;
    if (entry.isSymlink) {
      type = 'Symlink';
    } else if (entry.isDir) {
      type = 'Directory';
    } else {
      type = 'File';
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(entry.name, maxLines: 2, overflow: TextOverflow.ellipsis),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _PropRow('Type', type),
            if (location.isNotEmpty) _PropRow('Location', location),
            if (!entry.isDir) _PropRow('Size', formatSize(entry.size)),
            if (entry.mtime > 0) _PropRow('Modified', _formatMtime(entry.mtime)),
            if (entry.mode > 0) _PropRow('Permissions', _formatMode(entry.mode)),
            if (entry.isSymlink && entry.symlinkTarget != null) _PropRow('Links to', entry.symlinkTarget!),
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
      ),
    );
  }

  static String _formatMtime(int mtime) {
    final dt = DateTime.fromMillisecondsSinceEpoch(mtime * 1000).toLocal();
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}  $h:$m';
  }

  static String _formatMode(int mode) {
    final perm = mode & 0x1FF;
    const r = ['r', 'w', 'x'];
    final buf = StringBuffer();
    for (int i = 8; i >= 0; i--) {
      buf.write((perm >> i) & 1 == 1 ? r[i % 3] : '-');
    }
    return '${buf.toString()}  (${perm.toRadixString(8).padLeft(3, '0')})';
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

  String get _ext {
    final effectiveName = widget.entry.isSymlink && widget.entry.symlinkTarget != null
        ? widget.entry.symlinkTarget!.split('/').last
        : widget.entry.name;
    return effectiveName.contains('.') ? effectiveName.split('.').last.toLowerCase() : '';
  }

  Color get _bgColor {
    if (_ext == 'pdf') return Colors.grey.shade200;
    if (_kVideoExts.contains(_ext)) return Colors.black;
    if (_kImageExts.contains(_ext) || _ext == 'svg') return Colors.black;
    return const Color(0xFF272822);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        title: Text(widget.entry.name, style: const TextStyle(fontSize: 14)),
        backgroundColor: const Color(0xFF1E1E1E),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: FutureBuilder<Uint8List>(
        future: _contentFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(color: Colors.white),
                  const SizedBox(height: 16),
                  Text('Loading ${formatSize(widget.entry.size)}…', style: const TextStyle(color: Colors.white54)),
                ],
              ),
            );
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
          return _buildContent(snapshot.data!, _ext);
        },
      ),
    );
  }

  Widget _buildContent(Uint8List data, String ext) {
    if (_kImageExts.contains(ext)) {
      return InteractiveViewer(child: Center(child: Image.memory(data)));
    }
    if (ext == 'svg') {
      return InteractiveViewer(child: Center(child: SvgPicture.memory(data)));
    }
    if (_kTextExts.contains(ext)) {
      return _TextPreview(data: data);
    }
    if (ext == 'pdf') {
      return _PdfPreview(data: data);
    }
    if (_kVideoExts.contains(ext)) {
      return _VideoPreview(data: data, name: widget.entry.name);
    }
    if (_kAudioExts.contains(ext)) {
      return _AudioPreview(data: data, name: widget.entry.name);
    }
    return _UnknownPreview(entry: widget.entry, ext: ext);
  }
}

class _TextPreview extends StatelessWidget {
  final Uint8List data;
  const _TextPreview({required this.data});

  @override
  Widget build(BuildContext context) {
    try {
      final text = utf8.decode(data);
      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: SelectableText(
          text,
          style: const TextStyle(fontFamily: 'monospace', color: Color(0xFFF8F8F2), fontSize: 14),
        ),
      );
    } catch (_) {
      return const Center(
        child: Text('Cannot display binary file as text', style: TextStyle(color: Colors.white)),
      );
    }
  }
}

class _PdfPreview extends StatefulWidget {
  final Uint8List data;
  const _PdfPreview({required this.data});

  @override
  State<_PdfPreview> createState() => _PdfPreviewState();
}

class _PdfPreviewState extends State<_PdfPreview> {
  late PdfController _pdfController;

  @override
  void initState() {
    super.initState();
    _pdfController = PdfController(document: PdfDocument.openData(widget.data));
  }

  @override
  void dispose() {
    _pdfController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PdfView(controller: _pdfController, scrollDirection: Axis.vertical, pageSnapping: false);
  }
}

class _VideoPreview extends StatefulWidget {
  final Uint8List data;
  final String name;
  const _VideoPreview({required this.data, required this.name});

  @override
  State<_VideoPreview> createState() => _VideoPreviewState();
}

class _VideoPreviewState extends State<_VideoPreview> {
  VideoPlayerController? _vc;
  ChewieController? _cc;
  File? _tempFile;
  String? _error;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/${widget.name}');
      await file.writeAsBytes(widget.data);
      _tempFile = file;
      _vc = VideoPlayerController.file(file);
      await _vc!.initialize();
      _cc = ChewieController(
        videoPlayerController: _vc!,
        autoPlay: true,
        looping: false,
        allowFullScreen: true,
        allowMuting: true,
      );
      if (mounted) setState(() => _ready = true);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  void dispose() {
    _cc?.dispose();
    _vc?.dispose();
    _tempFile?.delete().catchError((Object _) => _tempFile!);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(
        child: Text('Error: $_error', style: const TextStyle(color: Colors.red)),
      );
    }
    if (!_ready) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }
    return Chewie(controller: _cc!);
  }
}

class _AudioPreview extends StatefulWidget {
  final Uint8List data;
  final String name;
  const _AudioPreview({required this.data, required this.name});

  @override
  State<_AudioPreview> createState() => _AudioPreviewState();
}

class _AudioPreviewState extends State<_AudioPreview> {
  final _player = AudioPlayer();
  PlayerState _state = PlayerState.stopped;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _player.onPlayerStateChanged.listen((s) {
      if (mounted) setState(() => _state = s);
    });
    _player.onPositionChanged.listen((p) {
      if (mounted) setState(() => _position = p);
    });
    _player.onDurationChanged.listen((d) {
      if (mounted) setState(() => _duration = d);
    });
    _player.play(BytesSource(widget.data));
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final isPlaying = _state == PlayerState.playing;
    final progress = _duration.inMilliseconds > 0
        ? (_position.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.audiotrack, size: 96, color: Colors.white54),
            const SizedBox(height: 24),
            Text(
              widget.name,
              style: const TextStyle(color: Colors.white, fontSize: 16),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 32),
            Slider(
              value: progress,
              onChanged: (v) => _player.seek(Duration(milliseconds: (v * _duration.inMilliseconds).round())),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_fmt(_position), style: const TextStyle(color: Colors.white54, fontSize: 12)),
                  Text(_fmt(_duration), style: const TextStyle(color: Colors.white54, fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.replay_10, color: Colors.white70, size: 32),
                  onPressed: () =>
                      _player.seek(Duration(seconds: (_position.inSeconds - 10).clamp(0, _duration.inSeconds))),
                ),
                const SizedBox(width: 16),
                IconButton(
                  icon: Icon(
                    isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                    color: Colors.white,
                    size: 64,
                  ),
                  onPressed: () => isPlaying ? _player.pause() : _player.resume(),
                ),
                const SizedBox(width: 16),
                IconButton(
                  icon: const Icon(Icons.forward_10, color: Colors.white70, size: 32),
                  onPressed: () =>
                      _player.seek(Duration(seconds: (_position.inSeconds + 10).clamp(0, _duration.inSeconds))),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _UnknownPreview extends StatelessWidget {
  final FileEntry entry;
  final String ext;
  const _UnknownPreview({required this.entry, required this.ext});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.insert_drive_file, size: 80, color: Colors.grey.shade600),
          const SizedBox(height: 16),
          Text(
            entry.name,
            style: const TextStyle(color: Colors.white, fontSize: 16),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text('Size: ${formatSize(entry.size)}', style: const TextStyle(color: Colors.white54)),
          if (ext.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('.${ext.toUpperCase()} file', style: const TextStyle(color: Colors.white38, fontSize: 12)),
          ],
          const SizedBox(height: 24),
          const Text('No preview available for this file type', style: TextStyle(color: Colors.white38)),
        ],
      ),
    );
  }
}

class _FileEntryTile extends StatelessWidget {
  final FileEntry entry;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _FileEntryTile({required this.entry, required this.onTap, required this.onLongPress});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final effectiveName = entry.isSymlink && entry.symlinkTarget != null
        ? entry.symlinkTarget!.split('/').last
        : entry.name;
    final ext = effectiveName.contains('.') ? effectiveName.split('.').last.toLowerCase() : '';

    final Widget leadingIcon;
    if (entry.isSymlink) {
      leadingIcon = Icon(Icons.link, color: isDark ? const Color(0xFFCBD5E1) : DeskconnColors.secondary, size: 36);
    } else {
      leadingIcon = Icon(
        entry.isDir ? Icons.folder : _getFileIcon(ext),
        color: entry.isDir
            ? (isDark ? const Color(0xFFE2E8F0) : DeskconnColors.primary)
            : _getFileIconColor(ext, isDark: isDark),
        size: 36,
      );
    }

    Widget? subtitle;
    if (entry.isSymlink && entry.symlinkTarget != null) {
      subtitle = Text(
        '→ ${entry.symlinkTarget}',
        style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.secondary),
        overflow: TextOverflow.ellipsis,
      );
    } else if (!entry.isDir) {
      subtitle = Text(formatSize(entry.size));
    }

    return ListTile(
      leading: SizedBox(width: 40, height: 40, child: leadingIcon),
      title: Text(entry.name),
      subtitle: subtitle,
      onTap: onTap,
      onLongPress: onLongPress,
      trailing: IconButton(icon: const Icon(Icons.more_vert), onPressed: onLongPress),
    );
  }

  IconData _getFileIcon(String ext) {
    if (_kImageExts.contains(ext) || ext == 'svg') return Icons.image;
    if (_kVideoExts.contains(ext)) return Icons.movie;
    if (_kAudioExts.contains(ext)) return Icons.audiotrack;
    if (_kTextExts.contains(ext)) return Icons.description;
    switch (ext) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'zip':
      case 'rar':
      case '7z':
      case 'tar':
      case 'gz':
      case 'xz':
      case 'bz2':
        return Icons.archive;
      case 'apk':
        return Icons.android;
      case 'exe':
      case 'msi':
      case 'dmg':
        return Icons.computer;
      case 'db':
      case 'sqlite':
      case 'sqlite3':
        return Icons.storage;
      default:
        return Icons.insert_drive_file;
    }
  }

  Color? _getFileIconColor(String ext, {required bool isDark}) {
    if (_kVideoExts.contains(ext)) {
      return isDark ? const Color(0xFF93C5FD) : const Color(0xFF64748B);
    }
    if (_kAudioExts.contains(ext)) {
      return isDark ? const Color(0xFFC4B5FD) : const Color(0xFF475569);
    }
    if (_kTextExts.contains(ext)) {
      return isDark ? const Color(0xFF86EFAC) : const Color(0xFF334155);
    }
    switch (ext) {
      case 'pdf':
        return isDark ? const Color(0xFFFCA5A5) : Colors.red.shade400;
      case 'zip':
      case 'rar':
      case '7z':
      case 'tar':
      case 'gz':
        return isDark ? const Color(0xFFFCD34D) : const Color(0xFF475569);
      default:
        return isDark ? const Color(0xFFCBD5E1) : null;
    }
  }
}

class _PropRow extends StatelessWidget {
  final String label;
  final String value;

  const _PropRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(label, style: TextStyle(fontSize: 13, color: muted)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 13), overflow: TextOverflow.visible),
          ),
        ],
      ),
    );
  }
}
