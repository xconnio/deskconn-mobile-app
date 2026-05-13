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
import 'package:deskconn_mobile_app/core/shell/shell_background_service.dart';

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

  String get _ext => widget.entry.name.contains('.') ? widget.entry.name.split('.').last.toLowerCase() : '';

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
    final ext = entry.name.contains('.') ? entry.name.split('.').last.toLowerCase() : '';
    final isImage = _kImageExts.contains(ext);

    return ListTile(
      leading: SizedBox(
        width: 40,
        height: 40,
        child: isImage
            ? FutureBuilder<Uint8List>(
                future: controller.thumbnail(parentPath == '/' ? '/${entry.name}' : '$parentPath/${entry.name}'),
                builder: (context, snapshot) {
                  if (snapshot.hasData) {
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: Image.memory(snapshot.data!, fit: BoxFit.cover),
                    );
                  }
                  if (snapshot.hasError) {
                    return Icon(Icons.image_not_supported, color: Colors.grey[400], size: 20);
                  }
                  return Icon(Icons.image, color: Colors.grey[400]);
                },
              )
            : Icon(
                entry.isDir ? Icons.folder : _getFileIcon(ext),
                color: entry.isDir ? Colors.amber : _getFileIconColor(ext),
              ),
      ),
      title: Text(entry.name),
      subtitle: entry.isDir ? null : Text(formatSize(entry.size)),
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

  Color? _getFileIconColor(String ext) {
    if (_kVideoExts.contains(ext)) return Colors.blue.shade300;
    if (_kAudioExts.contains(ext)) return Colors.purple.shade300;
    if (_kTextExts.contains(ext)) return Colors.teal.shade300;
    switch (ext) {
      case 'pdf':
        return Colors.red.shade400;
      case 'zip':
      case 'rar':
      case '7z':
      case 'tar':
      case 'gz':
        return Colors.orange.shade400;
      default:
        return null;
    }
  }
}
