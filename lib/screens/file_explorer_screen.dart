import 'dart:io';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:pdfx/pdfx.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:deskconn_mobile_app/core/wamp/desktop_connection_manager.dart';
import 'package:deskconn_mobile_app/core/file_explorer/file_explorer_controller.dart';
import 'package:deskconn_mobile_app/core/file_explorer/models.dart';
import 'package:deskconn_mobile_app/core/file_explorer/utils.dart';
import 'package:deskconn_mobile_app/core/terminal/terminal_background_service.dart';
import 'package:deskconn_mobile_app/theme/colors.dart';

class FileExplorerScreen extends StatefulWidget {
  final DesktopSessionLaunchConfig config;
  final String? initialPath;
  final String? initialOpenFile;
  final String? category;

  const FileExplorerScreen({super.key, required this.config, this.initialPath, this.initialOpenFile, this.category});

  @override
  State<FileExplorerScreen> createState() => _FileExplorerScreenState();
}

class _FileExplorerScreenState extends State<FileExplorerScreen> {
  FileExplorerController? _controller;
  FileBrowseResult? _currentBrowse;
  bool _isLoading = true;
  String? _error;
  bool _showHidden = false;
  String? _currentCategory;

  bool _isGrid = false;
  bool _isSearching = false;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

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

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _exitSearch() {
    setState(() {
      _isSearching = false;
      _searchQuery = '';
      _searchController.clear();
    });
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

    if (mounted) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

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
      if (mounted) _controller = FileExplorerController(connection.session, widget.config.realm);

      if (widget.category != null) {
        await _loadPath('', category: widget.category);
      } else {
        await _loadPath(widget.initialPath ?? '');
      }

      if (widget.initialOpenFile != null && _currentBrowse != null) {
        final entry = _currentBrowse!.entries.where((e) => _fullPath(e) == widget.initialOpenFile).firstOrNull;
        if (entry != null && mounted) {
          _onEntryTap(entry);
        }
      }
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

  Future<void> _loadPath(String path, {String? category}) async {
    if (_controller == null) return;

    final cacheKey = category != null ? '${widget.config.realm}:cat:$category' : '${widget.config.realm}:$path';
    if (_browseCache.containsKey(cacheKey)) {
      _log('browse cache hit path=$path category=$category');
      if (mounted) {
        setState(() {
          _currentBrowse = _browseCache[cacheKey];
          _currentCategory = category;
          _isLoading = false;
        });
      }
      _refreshPath(path, category: category);
      return;
    }

    if (mounted) setState(() => _isLoading = true);
    await _refreshPath(path, category: category);
  }

  Future<void> _refreshPath(String path, {String? category}) async {
    try {
      _log('browse path=$path category=$category');
      final FileBrowseResult result;
      if (category == 'documents') {
        // Web app merges these three categories for the 'Documents' view
        final results = await Future.wait([
          _controller!.index('pdfs'),
          _controller!.index('texts'),
          _controller!.index('documents'),
        ]);

        final allEntries = <FileEntry>[];
        for (final res in results) {
          allEntries.addAll(res.entries);
          // Assuming FileBrowseResult might have a status field in the future,
          // for now we just merge entries.
        }

        // Sort by mtime descending (newest first) to match web app
        allEntries.sort((a, b) => b.mtime.compareTo(a.mtime));

        result = FileBrowseResult(path: 'cat:documents', homePath: '/', entries: allEntries);
      } else if (category != null) {
        result = await _controller!.index(category);
      } else {
        result = await _controller!.browse(path);
      }

      final cacheKey = category != null ? '${widget.config.realm}:cat:$category' : '${widget.config.realm}:$path';
      _browseCache[cacheKey] = result;
      if (mounted) {
        setState(() {
          _currentBrowse = result;
          _currentCategory = category;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      final errorStr = e.toString();
      if (errorStr.contains('wamp.error.no_such_procedure') && category != null) {
        setState(() {
          _error = 'The remote desktop agent needs to be updated to support $category view.';
          _isLoading = false;
        });
        return;
      }
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
    if (mounted) setState(() => _isLoading = true);

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
      canPop: _currentCategory != null || (isAtRoot && !_isSearching),
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_isSearching) {
          _exitSearch();
        } else {
          _goUp();
        }
      },
      child: Scaffold(
        appBar: _isSearching ? _buildSearchAppBar() : _buildNormalAppBar(),
        drawer: _buildDrawer(),
        body: Column(
          children: [
            if (!_isSearching && _currentBrowse != null && _currentCategory == null)
              _Breadcrumbs(path: _currentBrowse!.path, onPathTap: _loadPath, onUpTap: _goUp),
            if (!_isSearching && _currentCategory != null) _buildCategoryHeader(),
            if (_clipboardEntry != null) _buildClipboardBanner(),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  AppBar _buildNormalAppBar() {
    String title = 'File Explorer';
    if (_currentCategory != null) {
      title = switch (_currentCategory) {
        'images' => 'Pictures',
        'videos' => 'Videos',
        'documents' => 'Documents',
        'pdfs' => 'PDFs',
        'texts' => 'Texts',
        _ => _currentCategory![0].toUpperCase() + _currentCategory!.substring(1),
      };
    }
    return AppBar(
      title: Text(title),
      actions: [
        if (_controller != null && _currentBrowse != null && _currentCategory == null)
          IconButton(icon: const Icon(Icons.add), tooltip: 'Upload file', onPressed: _uploadFile),
        IconButton(
          icon: const Icon(Icons.search),
          tooltip: 'Search',
          onPressed: () => setState(() => _isSearching = true),
        ),
        IconButton(
          icon: Icon(_isGrid ? Icons.view_list : Icons.grid_view),
          tooltip: _isGrid ? 'List view' : 'Grid view',
          onPressed: () => setState(() => _isGrid = !_isGrid),
        ),
        if (_currentCategory == null)
          IconButton(
            icon: Icon(_showHidden ? Icons.visibility : Icons.visibility_off),
            onPressed: () => setState(() => _showHidden = !_showHidden),
            tooltip: 'Show hidden files',
          ),
        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: () => _loadPath(_currentBrowse?.path ?? '', category: _currentCategory),
        ),
      ],
    );
  }

  AppBar _buildSearchAppBar() {
    return AppBar(
      leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: _exitSearch),
      title: TextField(
        controller: _searchController,
        autofocus: true,
        decoration: const InputDecoration(hintText: 'Search files…', border: InputBorder.none),
        onChanged: (q) => setState(() => _searchQuery = q),
      ),
      actions: [
        if (_searchQuery.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => setState(() {
              _searchQuery = '';
              _searchController.clear();
            }),
          ),
      ],
    );
  }

  Widget _buildCategoryHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: Theme.of(context).cardColor,
      child: Row(
        children: [
          const Icon(Icons.category_outlined, size: 20, color: Colors.grey),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Showing all ${_currentCategory == 'images' ? 'pictures' : _currentCategory} on this desktop',
              style: TextStyle(color: Theme.of(context).hintColor, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            const DrawerHeader(
              decoration: BoxDecoration(color: DeskconnColors.primary),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.folder_shared, size: 48, color: Colors.white),
                    SizedBox(height: 12),
                    Text(
                      'File Explorer',
                      style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: const Text('All Files'),
              selected: _currentCategory == null,
              onTap: () {
                Navigator.pop(context);
                _loadPath('');
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: const Text('Pictures'),
              selected: _currentCategory == 'images',
              onTap: () {
                Navigator.pop(context);
                _loadPath('', category: 'images');
              },
            ),
            ListTile(
              leading: const Icon(Icons.video_library_outlined),
              title: const Text('Videos'),
              selected: _currentCategory == 'videos',
              onTap: () {
                Navigator.pop(context);
                _loadPath('', category: 'videos');
              },
            ),
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: const Text('Documents'),
              selected: _currentCategory == 'documents',
              onTap: () {
                Navigator.pop(context);
                _loadPath('', category: 'documents');
              },
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_outlined),
              title: const Text('PDFs'),
              selected: _currentCategory == 'pdfs',
              onTap: () {
                Navigator.pop(context);
                _loadPath('', category: 'pdfs');
              },
            ),
            ListTile(
              leading: const Icon(Icons.text_snippet_outlined),
              title: const Text('Texts'),
              selected: _currentCategory == 'texts',
              onTap: () {
                Navigator.pop(context);
                _loadPath('', category: 'texts');
              },
            ),
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

    final q = _searchQuery.toLowerCase();
    final entries =
        _currentBrowse?.entries.where((e) {
          if (!_showHidden && e.name.startsWith('.')) return false;
          if (q.isNotEmpty && !e.name.toLowerCase().contains(q)) return false;
          return true;
        }).toList() ??
        [];

    if (entries.isEmpty) {
      return Center(
        child: Text(
          q.isNotEmpty ? 'No results for "$_searchQuery"' : 'No files found',
          style: TextStyle(color: Theme.of(context).hintColor),
        ),
      );
    }

    if (_isGrid) {
      return GridView.builder(
        padding: const EdgeInsets.all(8),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          mainAxisSpacing: 4,
          crossAxisSpacing: 4,
          childAspectRatio: 0.8,
        ),
        itemCount: entries.length,
        itemBuilder: (context, index) {
          final entry = entries[index];
          return _FileEntryGrid(
            entry: entry,
            onTap: () => _onEntryTap(entry),
            onLongPress: () => _showEntryOptions(entry),
            highlight: q.isNotEmpty ? q : null,
          );
        },
      );
    }

    return ListView.builder(
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        return _FileEntryTile(
          entry: entry,
          onTap: () => _onEntryTap(entry),
          onLongPress: () => _showEntryOptions(entry),
          highlight: q.isNotEmpty ? q : null,
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
            Icon(_clipboardIsCut ? Icons.drive_file_move_outlined : Icons.content_copy, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${_clipboardIsCut ? 'Move' : 'Copied'}: ${_clipboardEntry!.name}',
                style: const TextStyle(fontSize: 13),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            TextButton(onPressed: _pasteHere, child: Text(_clipboardIsCut ? 'Move here' : 'Paste here')),
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
      if (mounted) {
        setState(() {
          _clipboardEntry = null;
          _clipboardIsCut = false;
        });
      }
      _invalidateCacheFor(destDir);
      _loadPath(destDir);
    } catch (e) {
      if (mounted) _showErrorSnackBar('Paste failed: $e');
    }
  }

  void _invalidateCacheFor(String path) {
    _browseCache.remove('${widget.config.realm}:$path');
  }

  Future<void> _downloadFile(FileEntry entry) async {
    final path = _fullPath(entry);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 20),
            Expanded(child: Text('Downloading ${entry.name}…', overflow: TextOverflow.ellipsis)),
          ],
        ),
      ),
    );

    try {
      final bytes = await _controller!.read(path);
      final savedPath = await saveToDevice(entry.name, bytes);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Saved: $savedPath'), duration: const Duration(seconds: 5)));
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        _showErrorSnackBar('Download failed: $e');
      }
    }
  }

  Future<void> _uploadFile() async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: false);
    if (!mounted || result == null || result.files.isEmpty) return;

    final picked = result.files.first;
    final localPath = picked.path;
    if (localPath == null) {
      _showErrorSnackBar('Cannot get file path');
      return;
    }

    final remotePath = _currentBrowse!.path;
    if (!mounted) return;

    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    int totalBytes = 0;
    try {
      totalBytes = (await File(localPath).stat()).size;
    } catch (_) {}

    if (!mounted) return;

    final progressNotifier = ValueNotifier<double>(0.0);
    final statusNotifier = ValueNotifier<String>(
      totalBytes > 0 ? '0 B / ${formatSize(totalBytes)}  (0%)' : 'Preparing…',
    );

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: Text(picked.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ValueListenableBuilder<double>(
                valueListenable: progressNotifier,
                builder: (_, progress, _) => LinearProgressIndicator(value: progress),
              ),
              const SizedBox(height: 10),
              ValueListenableBuilder<String>(
                valueListenable: statusNotifier,
                builder: (_, status, _) => Text(status, style: const TextStyle(fontSize: 13)),
              ),
            ],
          ),
        ),
      ),
    );

    try {
      await _controller!.upload(
        localPath,
        remotePath,
        onProgress: (sent, total) {
          if (total <= 0) return;
          final fraction = (sent / total).clamp(0.0, 1.0);
          progressNotifier.value = fraction;
          final pct = (fraction * 100).toStringAsFixed(0);
          statusNotifier.value = '${formatSize(sent)} / ${formatSize(total)}  ($pct%)';
        },
      );
      progressNotifier.value = 1.0;
      statusNotifier.value = 'Done';
      if (mounted) {
        nav.pop();
        messenger.showSnackBar(SnackBar(content: Text('${picked.name} uploaded')));
        _invalidateCacheFor(remotePath);
        _loadPath(remotePath);
      }
    } catch (e) {
      if (mounted) {
        nav.pop();
        _showErrorSnackBar('Upload failed: $e');
      }
    }
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
            if (!entry.isDir)
              ListTile(
                leading: const Icon(Icons.download_outlined),
                title: const Text('Download'),
                onTap: () {
                  Navigator.pop(context);
                  _downloadFile(entry);
                },
              ),
            if (!entry.isDir)
              ListTile(
                leading: const Icon(Icons.open_in_new_outlined),
                title: const Text('Open with...'),
                onTap: () {
                  Navigator.pop(context);
                  _showOpenWithDialog(entry);
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
              leading: const Icon(Icons.drive_file_move_outlined),
              title: const Text('Move'),
              onTap: () {
                Navigator.pop(context);
                setState(() {
                  _clipboardEntry = entry;
                  _clipboardIsCut = true;
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('"${entry.name}" ready to move - navigate to destination and tap Move here')),
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

  void _showOpenWithDialog(FileEntry entry) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Text(
                'Open "${entry.name}" as:',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: const Text('Text'),
              onTap: () {
                Navigator.pop(context);
                _openFileAs(entry, 'text');
              },
            ),
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: const Text('Image'),
              onTap: () {
                Navigator.pop(context);
                _openFileAs(entry, 'image');
              },
            ),
            ListTile(
              leading: const Icon(Icons.movie_outlined),
              title: const Text('Video'),
              onTap: () {
                Navigator.pop(context);
                _openFileAs(entry, 'video');
              },
            ),
            ListTile(
              leading: const Icon(Icons.audiotrack_outlined),
              title: const Text('Audio'),
              onTap: () {
                Navigator.pop(context);
                _openFileAs(entry, 'audio');
              },
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_outlined),
              title: const Text('PDF'),
              onTap: () {
                Navigator.pop(context);
                _openFileAs(entry, 'pdf');
              },
            ),
          ],
        ),
      ),
    );
  }

  void _openFileAs(FileEntry entry, String type) {
    final path = entry.isSymlink ? (_resolveSymlinkTarget(entry) ?? _fullPath(entry)) : _fullPath(entry);
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            FilePreviewScreen(controller: _controller!, entry: entry, path: path, openAs: type),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
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

/// Save [bytes] to the public Downloads folder via the native MediaStore API
/// (Android 10+) or direct file write (Android 9). Falls back to app-specific
/// external storage if the native channel fails.
Future<String> saveToDevice(String filename, Uint8List bytes) async {
  try {
    final path = await const MethodChannel(
      'deskconn/file',
    ).invokeMethod<String>('saveToDownloads', {'filename': filename, 'bytes': bytes});
    return path ?? 'Downloads/$filename';
  } catch (_) {
    // Fallback: app-specific external storage
    Directory? base;
    try {
      base = await getExternalStorageDirectory();
    } catch (_) {
      base = await getApplicationDocumentsDirectory();
    }
    final dir = Directory('${base!.path}/Downloads');
    await dir.create(recursive: true);
    var target = File('${dir.path}/$filename');
    if (await target.exists()) {
      final dot = filename.lastIndexOf('.');
      final stem = dot > 0 ? filename.substring(0, dot) : filename;
      final ext = dot > 0 ? filename.substring(dot) : '';
      int n = 1;
      while (await target.exists()) {
        target = File('${dir.path}/$stem ($n)$ext');
        n++;
      }
    }
    await target.writeAsBytes(bytes);
    return target.path;
  }
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
  final String? openAs;

  const FilePreviewScreen({super.key, required this.controller, required this.entry, required this.path, this.openAs});

  @override
  State<FilePreviewScreen> createState() => _FilePreviewScreenState();
}

class _FilePreviewScreenState extends State<FilePreviewScreen> {
  Future<Uint8List>? _contentFuture;
  bool _isSaving = false;
  late final bool _streamMedia;

  @override
  void initState() {
    super.initState();
    final ext = _ext;
    final mode = widget.openAs;
    _streamMedia =
        mode == 'video' || mode == 'audio' || (mode == null && (kVideoExts.contains(ext) || kAudioExts.contains(ext)));
    if (!_streamMedia) {
      _contentFuture = widget.controller.read(widget.path);
    }
  }

  Future<Uint8List> _getContent() {
    _contentFuture ??= widget.controller.read(widget.path);
    return _contentFuture!;
  }

  Future<void> _download() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    try {
      final bytes = await _getContent();
      final savedPath = await saveToDevice(widget.entry.name, bytes);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Saved: $savedPath'), duration: const Duration(seconds: 5)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Download failed: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  String get _ext {
    final effectiveName = widget.entry.isSymlink && widget.entry.symlinkTarget != null
        ? widget.entry.symlinkTarget!.split('/').last
        : widget.entry.name;
    return effectiveName.contains('.') ? effectiveName.split('.').last.toLowerCase() : '';
  }

  Color get _bgColor {
    final effectiveExt = widget.openAs ?? _ext;
    if (effectiveExt == 'pdf') return Colors.grey.shade200;
    if (effectiveExt == 'video' || kVideoExts.contains(effectiveExt)) return Colors.black;
    if (effectiveExt == 'image' || effectiveExt == 'svg' || kImageExts.contains(effectiveExt)) return Colors.black;
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
        actions: [
          _isSaving
              ? const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    ),
                  ),
                )
              : IconButton(icon: const Icon(Icons.download_outlined), tooltip: 'Save to device', onPressed: _download),
        ],
      ),
      body: _streamMedia
          ? _buildMediaContent(_ext)
          : FutureBuilder<Uint8List>(
              future: _contentFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(color: Colors.white),
                        const SizedBox(height: 16),
                        Text(
                          'Loading ${formatSize(widget.entry.size)}…',
                          style: const TextStyle(color: Colors.white54),
                        ),
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

  Widget _buildMediaContent(String ext) {
    final mode = widget.openAs;
    if (mode == 'video' || (mode == null && kVideoExts.contains(ext))) {
      return _VideoPreview(
        controller: widget.controller,
        path: widget.path,
        name: widget.entry.name,
        size: widget.entry.size,
      );
    }
    return _AudioPreview(controller: widget.controller, path: widget.path, name: widget.entry.name);
  }

  Widget _buildContent(Uint8List data, String ext) {
    final mode = widget.openAs;
    if (mode != null) {
      if (mode == 'text') return _TextPreview(data: data);
      if (mode == 'image') return InteractiveViewer(child: Center(child: Image.memory(data)));
      if (mode == 'pdf') return _PdfPreview(data: data);
    }

    if (kImageExts.contains(ext)) {
      return InteractiveViewer(child: Center(child: Image.memory(data)));
    }
    if (ext == 'svg') {
      return InteractiveViewer(child: Center(child: SvgPicture.memory(data)));
    }
    if (kTextExts.contains(ext)) {
      return _TextPreview(data: data);
    }
    if (ext == 'pdf') {
      return _PdfPreview(data: data);
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
  final FileExplorerController controller;
  final String path;
  final String name;
  final int size;
  const _VideoPreview({required this.controller, required this.path, required this.name, this.size = 0});

  @override
  State<_VideoPreview> createState() => _VideoPreviewState();
}

class _VideoPreviewState extends State<_VideoPreview> with WidgetsBindingObserver {
  VideoPlayerController? _vc;
  ChewieController? _cc;
  File? _tempFile;
  String? _error;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  Future<void> _init() async {
    try {
      final bytes = await widget.controller.read(widget.path);
      if (!mounted) return;
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/${widget.name}');
      await file.writeAsBytes(bytes);
      _tempFile = file;
      _vc = VideoPlayerController.file(file);
      await _vc!.initialize();
      if (!mounted) {
        _vc!.dispose();
        file.delete().catchError((Object _) => file);
        return;
      }
      _cc = ChewieController(
        videoPlayerController: _vc!,
        autoPlay: true,
        looping: false,
        allowFullScreen: true,
        allowMuting: true,
      );
      setState(() => _ready = true);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _vc?.pause();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: Colors.white),
            const SizedBox(height: 16),
            if (widget.size > 0)
              Text('Loading ${formatSize(widget.size)}…', style: const TextStyle(color: Colors.white54)),
          ],
        ),
      );
    }
    return Chewie(controller: _cc!);
  }
}

class _AudioPreview extends StatefulWidget {
  final FileExplorerController controller;
  final String path;
  final String name;
  const _AudioPreview({required this.controller, required this.path, required this.name});

  @override
  State<_AudioPreview> createState() => _AudioPreviewState();
}

class _AudioPreviewState extends State<_AudioPreview> with WidgetsBindingObserver {
  final _player = AudioPlayer();
  PlayerState _state = PlayerState.stopped;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  String? _error;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _player.onPlayerStateChanged.listen((s) {
      if (mounted) setState(() => _state = s);
    });
    _player.onPositionChanged.listen((p) {
      if (mounted) setState(() => _position = p);
    });
    _player.onDurationChanged.listen((d) {
      if (mounted) setState(() => _duration = d);
    });
    _load();
  }

  Future<void> _load() async {
    try {
      final bytes = await widget.controller.read(widget.path);
      if (!mounted) return;
      await _player.play(BytesSource(bytes));
      if (mounted) setState(() => _loaded = true);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _player.pause();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
    if (_error != null) {
      return Center(
        child: Text('Error: $_error', style: const TextStyle(color: Colors.red)),
      );
    }
    if (!_loaded) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }
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

class _FileEntryGrid extends StatelessWidget {
  final FileEntry entry;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final String? highlight;

  const _FileEntryGrid({required this.entry, required this.onTap, required this.onLongPress, this.highlight});

  @override
  Widget build(BuildContext context) {
    final effectiveName = entry.isSymlink && entry.symlinkTarget != null
        ? entry.symlinkTarget!.split('/').last
        : entry.name;
    final ext = effectiveName.contains('.') ? effectiveName.split('.').last.toLowerCase() : '';

    final name = entry.name;
    final q = highlight?.toLowerCase() ?? '';
    final nameWidget = q.isNotEmpty && name.toLowerCase().contains(q)
        ? _buildHighlightedName(context, name, q)
        : Text(
            name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 11),
          );

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _FileEntryVisual(entry: entry, ext: ext, size: 56, iconSize: 44),
          const SizedBox(height: 4),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 2), child: nameWidget),
        ],
      ),
    );
  }

  Widget _buildHighlightedName(BuildContext context, String name, String q) {
    final lower = name.toLowerCase();
    final idx = lower.indexOf(q);
    if (idx < 0) {
      return Text(
        name,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 11),
      );
    }
    final color = Theme.of(context).colorScheme.primary;
    return RichText(
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      text: TextSpan(
        style: DefaultTextStyle.of(context).style.copyWith(fontSize: 11),
        children: [
          if (idx > 0) TextSpan(text: name.substring(0, idx)),
          TextSpan(
            text: name.substring(idx, idx + q.length),
            style: TextStyle(color: color, fontWeight: FontWeight.bold),
          ),
          if (idx + q.length < name.length) TextSpan(text: name.substring(idx + q.length)),
        ],
      ),
    );
  }
}

class _FileEntryTile extends StatelessWidget {
  final FileEntry entry;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final String? highlight;

  const _FileEntryTile({required this.entry, required this.onTap, required this.onLongPress, this.highlight});

  @override
  Widget build(BuildContext context) {
    final effectiveName = entry.isSymlink && entry.symlinkTarget != null
        ? entry.symlinkTarget!.split('/').last
        : entry.name;
    final ext = effectiveName.contains('.') ? effectiveName.split('.').last.toLowerCase() : '';

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
      leading: _FileEntryVisual(entry: entry, ext: ext, size: 40, iconSize: 34),
      title: _buildTitle(context),
      subtitle: subtitle,
      onTap: onTap,
      onLongPress: onLongPress,
      trailing: IconButton(icon: const Icon(Icons.more_vert), onPressed: onLongPress),
    );
  }

  Widget _buildTitle(BuildContext context) {
    final name = entry.name;
    final q = highlight;
    if (q == null || q.isEmpty) return Text(name);
    final lower = name.toLowerCase();
    final idx = lower.indexOf(q);
    if (idx < 0) return Text(name);
    final color = Theme.of(context).colorScheme.primary;
    return RichText(
      text: TextSpan(
        style: DefaultTextStyle.of(context).style,
        children: [
          if (idx > 0) TextSpan(text: name.substring(0, idx)),
          TextSpan(
            text: name.substring(idx, idx + q.length),
            style: TextStyle(color: color, fontWeight: FontWeight.bold),
          ),
          if (idx + q.length < name.length) TextSpan(text: name.substring(idx + q.length)),
        ],
      ),
    );
  }
}

class _FileEntryVisual extends StatelessWidget {
  final FileEntry entry;
  final String ext;
  final double size;
  final double iconSize;

  const _FileEntryVisual({required this.entry, required this.ext, required this.size, required this.iconSize});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final thumbnail = _decodeThumbnail(entry.thumbnail);
    final isVideo = kVideoExts.contains(ext);

    if (thumbnail != null && !entry.isDir && !entry.isSymlink) {
      return SizedBox.square(
        dimension: size,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(color: isDark ? const Color(0xFF111827) : const Color(0xFFE2E8F0)),
              Image.memory(thumbnail, fit: BoxFit.cover, gaplessPlayback: true),
              if (isVideo)
                const Align(
                  alignment: Alignment.center,
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: Color(0x99000000), shape: BoxShape.circle),
                    child: Padding(
                      padding: EdgeInsets.all(3),
                      child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: 20),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    }

    final IconData iconData;
    final Color iconColor;
    if (entry.isSymlink) {
      iconData = Icons.link;
      iconColor = isDark ? const Color(0xFFCBD5E1) : DeskconnColors.secondary;
    } else if (entry.isDir) {
      iconData = Icons.folder;
      iconColor = isDark ? const Color(0xFFE2E8F0) : DeskconnColors.primary;
    } else {
      iconData = getFileIcon(ext);
      iconColor = getFileIconColor(ext, isDark: isDark) ?? (isDark ? const Color(0xFFCBD5E1) : Colors.blueGrey);
    }

    return SizedBox.square(
      dimension: size,
      child: Center(
        child: Icon(iconData, color: iconColor, size: iconSize),
      ),
    );
  }

  Uint8List? _decodeThumbnail(String? value) {
    if (value == null || value.isEmpty) return null;
    try {
      return base64Decode(value);
    } catch (_) {
      return null;
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
