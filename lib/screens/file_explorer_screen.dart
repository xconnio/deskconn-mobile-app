import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:pdfx/pdfx.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:deskconn_mobile_app/core/wamp/desktop_connection_manager.dart';
import 'package:deskconn_mobile_app/core/file_explorer/file_explorer_controller.dart';
import 'package:deskconn_mobile_app/core/file_explorer/models.dart';
import 'package:deskconn_mobile_app/core/file_explorer/utils.dart';
import 'package:deskconn_mobile_app/core/terminal/terminal_background_service.dart';
import 'package:deskconn_mobile_app/screens/image_editor_screen.dart';
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
  static const int _pageSize = 200;

  FileExplorerController? _controller;
  FileBrowseResult? _currentBrowse;
  bool _isLoading = true;
  bool _isLoadingMore = false;
  String? _error;
  bool _showHidden = false;
  late String? _currentCategory = widget.category;
  final ScrollController _scrollController = ScrollController();

  bool _isGrid = false;
  bool get _isMediaGallery => _currentCategory == 'images' || _currentCategory == 'videos';
  bool _isSearching = false;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  List<FileEntry> _clipboardEntries = [];
  bool _clipboardIsCut = false;

  bool _selectionMode = false;
  final Set<String> _selectedPaths = {};

  static final Map<String, FileBrowseResult> _browseCache = {};

  void _log(String message) {
    debugPrint('[FileExplorer ${widget.config.realm} ${DateTime.now().toIso8601String()}] $message');
  }

  @override
  void initState() {
    super.initState();
    _initialize();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 300) {
      _loadMore();
    }
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
      _controller = existing.explorerController ??= FileExplorerController(existing.session, widget.config.realm);
      if (_controller!.isKeyExchanged) {
        await _loadInitial();
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
          );
      _log('controller ready p2p=${connection.isP2P}');
      if (mounted) {
        _controller = connection.explorerController ??= FileExplorerController(connection.session, widget.config.realm);
      }

      await _loadInitial();
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

  Future<void> _loadInitial() async {
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
        result = await _controller!.browse(path, limit: _pageSize);
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
      // isConnected() can keep reporting true even after the session's read
      // loop has died (a known issue in the underlying WAMP client), so a
      // call that timed out is treated as just as dead as a closed session —
      // otherwise every retry on this realm keeps reusing the same zombie
      // session and timing out forever.
      final sessionAlive = (_controller?.session.isConnected() ?? false) && e is! TimeoutException;
      if (!sessionAlive) {
        _log('session lost during browse path=$path error=$e');
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

  Future<void> _loadMore() async {
    final current = _currentBrowse;
    if (current == null || !current.hasMore || _isLoadingMore || _isLoading || _currentCategory != null) return;
    if (_controller == null) return;

    setState(() => _isLoadingMore = true);
    try {
      final more = await _controller!.browse(current.path, cursor: current.nextCursor, limit: _pageSize);
      final merged = FileBrowseResult(
        path: current.path,
        homePath: current.homePath,
        entries: [...current.entries, ...more.entries],
        nextCursor: more.nextCursor,
        hasMore: more.hasMore,
      );
      _browseCache['${widget.config.realm}:${current.path}'] = merged;
      if (mounted) {
        setState(() {
          _currentBrowse = merged;
          _isLoadingMore = false;
        });
      }
    } catch (e) {
      _log('load more failed path=${current.path} error=$e');
      if (mounted) setState(() => _isLoadingMore = false);
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
      final result = await _controller!.browse(browsePath, limit: _pageSize);
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

  Future<void> _onEntryTap(FileEntry entry) async {
    if (entry.isDir) {
      _loadPath(_fullPath(entry));
    } else if (entry.isSymlink) {
      _openSymlink(entry);
    } else {
      final didDelete = await Navigator.push<bool>(
        context,
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) =>
              FilePreviewScreen(controller: _controller!, entry: entry, path: _fullPath(entry)),
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
        ),
      );
      if (didDelete == true) {
        _invalidateCacheFor(_currentBrowse?.path ?? '');
        _loadPath(_currentBrowse?.path ?? '');
      }
    }
  }

  Future<void> _onGalleryEntryTap(List<FileEntry> entries, int index) async {
    final entry = entries[index];
    final didDelete = await Navigator.push<bool>(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => FilePreviewScreen(
          controller: _controller!,
          entry: entry,
          path: _fullPath(entry),
          galleryEntries: entries,
          galleryIndex: index,
          pathBuilder: _fullPath,
        ),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
    );
    if (didDelete == true) {
      if (_currentCategory != null) {
        _browseCache.remove('${widget.config.realm}:cat:$_currentCategory');
      } else {
        _invalidateCacheFor(_currentBrowse?.path ?? '');
      }
      _loadPath(_currentBrowse?.path ?? '', category: _currentCategory);
    }
  }

  void _enterSelectionMode(FileEntry entry) {
    setState(() {
      _selectionMode = true;
      _selectedPaths
        ..clear()
        ..add(_fullPath(entry));
    });
  }

  void _toggleSelection(FileEntry entry) {
    final path = _fullPath(entry);
    setState(() {
      if (!_selectedPaths.remove(path)) {
        _selectedPaths.add(path);
      }
      if (_selectedPaths.isEmpty) _selectionMode = false;
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _selectionMode = false;
      _selectedPaths.clear();
    });
  }

  void _selectAll() {
    setState(() {
      _selectedPaths
        ..clear()
        ..addAll(_visibleEntries().map(_fullPath));
    });
  }

  List<FileEntry> _visibleEntries() {
    final q = _searchQuery.toLowerCase();
    return _currentBrowse?.entries.where((e) {
          if (!_showHidden && e.name.startsWith('.')) return false;
          if (q.isNotEmpty && !e.name.toLowerCase().contains(q)) return false;
          return true;
        }).toList() ??
        [];
  }

  List<FileEntry> get _selectedEntries =>
      _currentBrowse?.entries.where((e) => _selectedPaths.contains(_fullPath(e))).toList() ?? [];

  Future<void> _bulkDelete() async {
    final entries = _selectedEntries;
    if (entries.isEmpty) return;
    final label = entries.length == 1 ? entries.first.name : '${entries.length} items';
    if (!await _confirmDelete(context, label)) return;

    var failed = 0;
    for (final entry in entries) {
      try {
        await _controller!.delete(_fullPath(entry));
      } catch (e) {
        failed++;
        _log('bulk delete failed path=${_fullPath(entry)} error=$e');
      }
    }

    if (!mounted) return;
    _exitSelectionMode();
    _invalidateCacheFor(_currentBrowse?.path ?? '');
    _loadPath(_currentBrowse?.path ?? '', category: _currentCategory);
    final ok = entries.length - failed;
    _showErrorSnackBar(
      failed == 0 ? 'Deleted $ok item${ok == 1 ? '' : 's'}' : 'Deleted $ok of ${entries.length}, $failed failed',
    );
  }

  void _bulkStageClipboard({required bool cut}) {
    final entries = _selectedEntries;
    if (entries.isEmpty) return;
    setState(() {
      _clipboardEntries = entries;
      _clipboardIsCut = cut;
    });
    _exitSelectionMode();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          cut
              ? '${entries.length} item${entries.length == 1 ? '' : 's'} ready to move - navigate to destination and tap Move here'
              : '${entries.length} item${entries.length == 1 ? '' : 's'} copied — navigate to destination and tap Paste here',
        ),
      ),
    );
  }

  Future<void> _bulkShare() async {
    final entries = _selectedEntries.where((e) => !e.isDir).toList();
    if (entries.isEmpty) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 20),
            Expanded(child: Text('Preparing files…')),
          ],
        ),
      ),
    );

    try {
      final files = <(String, Uint8List)>[];
      for (final entry in entries) {
        files.add((entry.name, await _controller!.read(_fullPath(entry))));
      }
      if (mounted) Navigator.pop(context);
      await shareFileBytesList(files);
      if (mounted) _exitSelectionMode();
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        _showErrorSnackBar('Share failed: $e');
      }
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
    final showSidebar = _isDesktopLayout(context);

    return PopScope(
      canPop: !_selectionMode && !_isSearching && (_currentCategory != null || isAtRoot),
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_selectionMode) {
          _exitSelectionMode();
        } else if (_isSearching) {
          _exitSearch();
        } else {
          _goUp();
        }
      },
      child: Scaffold(
        appBar: _selectionMode ? _buildSelectionAppBar() : (_isSearching ? _buildSearchAppBar() : _buildNormalAppBar()),
        drawer: showSidebar ? _buildDrawer() : null,
        body: Column(
          children: [
            if (!_isSearching && _currentBrowse != null && _currentCategory == null)
              _Breadcrumbs(
                path: _currentBrowse!.path,
                homePath: _currentBrowse!.homePath,
                onPathTap: _loadPath,
                onUpTap: _goUp,
              ),
            if (_clipboardEntries.isNotEmpty) _buildClipboardBanner(),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  AppBar _buildNormalAppBar() {
    String title = 'Files';
    if (_currentCategory != null) {
      title = switch (_currentCategory) {
        'images' => 'Photos',
        'videos' => 'Videos',
        'documents' => 'Documents',
        'pdfs' => 'PDFs',
        'texts' => 'Texts',
        _ => _currentCategory![0].toUpperCase() + _currentCategory!.substring(1),
      };
    }
    final isCompact = MediaQuery.sizeOf(context).width < 480;
    final canUpload = _controller != null && _currentBrowse != null && _currentCategory == null;
    final showHiddenToggle = _currentCategory == null;
    final secondaryActions = <PopupMenuEntry<String>>[
      if (!_isMediaGallery && isCompact)
        PopupMenuItem(
          value: 'toggleView',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(_isGrid ? Icons.view_list : Icons.grid_view),
            title: Text(_isGrid ? 'List view' : 'Grid view'),
          ),
        ),
      if (showHiddenToggle)
        PopupMenuItem(
          value: 'toggleHidden',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(_showHidden ? Icons.visibility : Icons.visibility_off),
            title: Text(_showHidden ? 'Hide hidden files' : 'Show hidden files'),
          ),
        ),
      if (isCompact)
        const PopupMenuItem(
          value: 'refresh',
          child: ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.refresh), title: Text('Refresh')),
        ),
    ];

    return AppBar(
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      actions: [
        if (canUpload) IconButton(icon: const Icon(Icons.add), tooltip: 'Upload file', onPressed: _uploadFile),
        IconButton(
          icon: const Icon(Icons.search),
          tooltip: 'Search',
          onPressed: () => setState(() => _isSearching = true),
        ),
        if (!isCompact && !_isMediaGallery)
          IconButton(
            icon: Icon(_isGrid ? Icons.view_list : Icons.grid_view),
            tooltip: _isGrid ? 'List view' : 'Grid view',
            onPressed: () => setState(() => _isGrid = !_isGrid),
          ),
        if (!isCompact)
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () => _loadPath(_currentBrowse?.path ?? '', category: _currentCategory),
          ),
        if (secondaryActions.isNotEmpty)
          PopupMenuButton<String>(
            tooltip: 'More',
            itemBuilder: (_) => secondaryActions,
            onSelected: _handleAppBarMenuAction,
          ),
      ],
    );
  }

  AppBar _buildSelectionAppBar() {
    final selected = _selectedEntries;
    final hasDir = selected.any((e) => e.isDir);
    final single = selected.length == 1 ? selected.first : null;

    return AppBar(
      leading: IconButton(icon: const Icon(Icons.close), onPressed: _exitSelectionMode),
      title: Text('${selected.length} selected'),
      actions: [
        PopupMenuButton<String>(
          tooltip: 'More',
          onSelected: (action) => _handleSelectionMenuAction(action, single),
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'selectAll', child: Text('Select all')),
            const PopupMenuItem(value: 'moveTo', child: Text('Move to')),
            const PopupMenuItem(value: 'copyTo', child: Text('Copy to')),
            if (single != null && !single.isDir) const PopupMenuItem(value: 'openWith', child: Text('Open with...')),
            if (single != null && !single.isDir) const PopupMenuItem(value: 'download', child: Text('Download')),
            if (!hasDir) const PopupMenuItem(value: 'share', child: Text('Share')),
            if (single != null) const PopupMenuItem(value: 'rename', child: Text('Rename')),
            const PopupMenuItem(value: 'delete', child: Text('Delete')),
            if (single != null) const PopupMenuItem(value: 'details', child: Text('Details')),
          ],
        ),
      ],
    );
  }

  void _handleSelectionMenuAction(String action, FileEntry? single) {
    switch (action) {
      case 'selectAll':
        _selectAll();
      case 'moveTo':
        _bulkStageClipboard(cut: true);
      case 'copyTo':
        _bulkStageClipboard(cut: false);
      case 'openWith':
        if (single != null) {
          _exitSelectionMode();
          _showOpenWithDialog(single);
        }
      case 'download':
        if (single != null) {
          _exitSelectionMode();
          _downloadFile(single);
        }
      case 'share':
        _bulkShare();
      case 'rename':
        if (single != null) {
          _exitSelectionMode();
          _showRenameDialog(single);
        }
      case 'delete':
        _bulkDelete();
      case 'details':
        if (single != null) _showProperties(single);
    }
  }

  void _handleAppBarMenuAction(String action) {
    switch (action) {
      case 'toggleView':
        setState(() => _isGrid = !_isGrid);
      case 'toggleHidden':
        setState(() => _showHidden = !_showHidden);
      case 'refresh':
        _loadPath(_currentBrowse?.path ?? '', category: _currentCategory);
    }
  }

  AppBar _buildSearchAppBar() {
    final colorScheme = Theme.of(context).colorScheme;
    return AppBar(
      titleSpacing: 0,
      leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: _exitSearch),
      title: Padding(
        padding: const EdgeInsets.only(right: 12),
        child: SearchBar(
          controller: _searchController,
          autoFocus: true,
          hintText: 'Search files…',
          leading: const Icon(Icons.search),
          trailing: [
            if (_searchQuery.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => setState(() {
                  _searchQuery = '';
                  _searchController.clear();
                }),
              ),
          ],
          elevation: const WidgetStatePropertyAll(0),
          backgroundColor: WidgetStatePropertyAll(colorScheme.surfaceContainerHighest),
          side: WidgetStatePropertyAll(BorderSide(color: colorScheme.outlineVariant)),
          onChanged: (q) => setState(() => _searchQuery = q),
        ),
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
                      'Files',
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
              title: const Text('Photos'),
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
    final entries = _visibleEntries();

    if (entries.isEmpty) {
      return Center(
        child: Text(
          q.isNotEmpty ? 'No results for "$_searchQuery"' : 'No files found',
          style: TextStyle(color: Theme.of(context).hintColor),
        ),
      );
    }

    if (_isMediaGallery) {
      return GridView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.all(2),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 2,
          crossAxisSpacing: 2,
          childAspectRatio: 1,
        ),
        itemCount: entries.length,
        itemBuilder: (context, index) {
          final entry = entries[index];
          return _MediaGalleryTile(
            entry: entry,
            selectionMode: _selectionMode,
            selected: _selectedPaths.contains(_fullPath(entry)),
            onTap: () => _selectionMode ? _toggleSelection(entry) : _onGalleryEntryTap(entries, index),
            onLongPress: () {
              if (!_selectionMode) _enterSelectionMode(entry);
            },
          );
        },
      );
    }

    if (_isGrid) {
      return GridView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.all(8),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          mainAxisSpacing: 4,
          crossAxisSpacing: 4,
          childAspectRatio: 0.8,
        ),
        itemCount: entries.length + (_isLoadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= entries.length) return const _LoadMoreIndicator();
          final entry = entries[index];
          return _FileEntryGrid(
            entry: entry,
            selectionMode: _selectionMode,
            selected: _selectedPaths.contains(_fullPath(entry)),
            onTap: () => _selectionMode ? _toggleSelection(entry) : _onEntryTap(entry),
            onLongPress: () {
              if (!_selectionMode) _enterSelectionMode(entry);
            },
            highlight: q.isNotEmpty ? q : null,
          );
        },
      );
    }

    return ListView.builder(
      controller: _scrollController,
      itemCount: entries.length + (_isLoadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= entries.length) return const _LoadMoreIndicator();
        final entry = entries[index];
        return _FileEntryTile(
          entry: entry,
          selectionMode: _selectionMode,
          selected: _selectedPaths.contains(_fullPath(entry)),
          onTap: () => _selectionMode ? _toggleSelection(entry) : _onEntryTap(entry),
          onLongPress: () {
            if (!_selectionMode) _enterSelectionMode(entry);
          },
          highlight: q.isNotEmpty ? q : null,
        );
      },
    );
  }

  Widget _buildClipboardBanner() {
    final colorScheme = Theme.of(context).colorScheme;
    final label = _clipboardEntries.length == 1 ? _clipboardEntries.first.name : '${_clipboardEntries.length} items';
    return ColoredBox(
      color: colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Row(
          children: [
            Icon(
              _clipboardIsCut ? Icons.drive_file_move_outlined : Icons.content_copy,
              size: 16,
              color: colorScheme.onSecondaryContainer,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${_clipboardIsCut ? 'Move' : 'Copied'}: $label',
                style: TextStyle(fontSize: 13, color: colorScheme.onSecondaryContainer),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: colorScheme.onSecondaryContainer),
              onPressed: _pasteHere,
              child: Text(_clipboardIsCut ? 'Move here' : 'Paste here'),
            ),
            IconButton(
              icon: Icon(Icons.close, size: 18, color: colorScheme.onSecondaryContainer),
              onPressed: () => setState(() {
                _clipboardEntries = [];
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
    if (_clipboardEntries.isEmpty || _currentBrowse == null) return;
    final entries = _clipboardEntries;
    final isCut = _clipboardIsCut;
    final destDir = _currentBrowse!.path;

    var failed = 0;
    for (final entry in entries) {
      final srcPath = entry.path;
      final srcDir = srcPath.substring(0, srcPath.lastIndexOf('/'));
      var destPath = '$destDir/${entry.name}';

      if (destPath == srcPath) {
        if (!isCut) {
          final name = entry.name;
          final dot = entry.isDir ? -1 : name.lastIndexOf('.');
          destPath = dot > 0
              ? '$destDir/${name.substring(0, dot)}_copy${name.substring(dot)}'
              : '$destDir/${name}_copy';
        } else {
          continue;
        }
      }

      try {
        if (isCut) {
          await _controller!.rename(srcPath, destPath);
          _invalidateCacheFor(srcDir);
        } else {
          await _controller!.copy(srcPath, destPath);
        }
      } catch (e) {
        failed++;
        _log('paste failed src=$srcPath dst=$destPath error=$e');
      }
    }

    if (mounted) {
      setState(() {
        _clipboardEntries = [];
        _clipboardIsCut = false;
      });
    }
    _invalidateCacheFor(destDir);
    _loadPath(destDir);
    if (failed > 0 && mounted) {
      _showErrorSnackBar('${entries.length - failed} of ${entries.length} pasted, $failed failed');
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

  Future<void> _openFileAs(FileEntry entry, String type) async {
    final path = entry.isSymlink ? (_resolveSymlinkTarget(entry) ?? _fullPath(entry)) : _fullPath(entry);
    final didDelete = await Navigator.push<bool>(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            FilePreviewScreen(controller: _controller!, entry: entry, path: path, openAs: type),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
    );
    if (didDelete == true) {
      _invalidateCacheFor(_currentBrowse?.path ?? '');
      _loadPath(_currentBrowse?.path ?? '');
    }
  }

  void _showProperties(FileEntry entry) {
    _showFileProperties(context, entry, fallbackLocation: _currentBrowse?.path ?? '');
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

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _LoadMoreIndicator extends StatelessWidget {
  const _LoadMoreIndicator();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 16),
      child: Center(child: SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))),
    );
  }
}

bool _isDesktopLayout(BuildContext context) {
  if (MediaQuery.sizeOf(context).width >= 900) return true;
  return switch (defaultTargetPlatform) {
    TargetPlatform.linux || TargetPlatform.macOS || TargetPlatform.windows => true,
    _ => false,
  };
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

// Downloads bytes are cached to a temp file since the OS share sheet needs a
// real file path, not raw bytes; the temp copy is cleaned up once the share
// sheet is dismissed.
Future<void> shareFileBytes(String filename, Uint8List bytes) async {
  final tempDir = await getTemporaryDirectory();
  final tempFile = File('${tempDir.path}/$filename');
  await tempFile.writeAsBytes(bytes);
  try {
    await SharePlus.instance.share(ShareParams(files: [XFile(tempFile.path)]));
  } finally {
    tempFile.delete().catchError((Object _) => tempFile);
  }
}

/// Same as [shareFileBytes] but for multiple files in a single share sheet.
Future<void> shareFileBytesList(List<(String, Uint8List)> files) async {
  final tempDir = await getTemporaryDirectory();
  final tempFiles = <File>[];
  try {
    for (final (filename, bytes) in files) {
      final tempFile = File('${tempDir.path}/$filename');
      await tempFile.writeAsBytes(bytes);
      tempFiles.add(tempFile);
    }
    await SharePlus.instance.share(ShareParams(files: tempFiles.map((f) => XFile(f.path)).toList()));
  } finally {
    for (final tempFile in tempFiles) {
      tempFile.delete().catchError((Object _) => tempFile);
    }
  }
}

void _showFileProperties(BuildContext context, FileEntry entry, {String fallbackLocation = ''}) {
  final location = entry.path.isNotEmpty ? entry.path.substring(0, entry.path.lastIndexOf('/')) : fallbackLocation;

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

String _formatMtime(int mtime) {
  final dt = DateTime.fromMillisecondsSinceEpoch(mtime * 1000).toLocal();
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final h = dt.hour.toString().padLeft(2, '0');
  final m = dt.minute.toString().padLeft(2, '0');
  return '${months[dt.month - 1]} ${dt.day}, ${dt.year}  $h:$m';
}

String _formatMode(int mode) {
  final perm = mode & 0x1FF;
  const r = ['r', 'w', 'x'];
  final buf = StringBuffer();
  for (int i = 8; i >= 0; i--) {
    buf.write((perm >> i) & 1 == 1 ? r[i % 3] : '-');
  }
  return '${buf.toString()}  (${perm.toRadixString(8).padLeft(3, '0')})';
}

Future<bool> _confirmDelete(BuildContext context, String name) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Delete'),
      content: Text('Are you sure you want to delete $name?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Delete', style: TextStyle(color: Colors.red)),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

class _Breadcrumbs extends StatelessWidget {
  final String path;
  final String homePath;
  final Function(String) onPathTap;
  final VoidCallback onUpTap;

  const _Breadcrumbs({required this.path, required this.homePath, required this.onPathTap, required this.onUpTap});

  @override
  Widget build(BuildContext context) {
    final crumbs = _crumbs();

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
                  for (var i = 0; i < crumbs.length; i++) ...[
                    if (i > 0) const Icon(Icons.chevron_right, size: 16),
                    TextButton(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: () {
                        onPathTap(crumbs[i].path);
                      },
                      child: Text(crumbs[i].label),
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

  List<_BreadcrumbPart> _crumbs() {
    final normalizedPath = _normalizePath(path);
    final normalizedHome = _normalizePath(homePath);
    final homeLabel = normalizedHome;

    if (normalizedPath == normalizedHome || !normalizedPath.startsWith('$normalizedHome/')) {
      return [_BreadcrumbPart(homeLabel, normalizedHome)];
    }

    final relativeParts = normalizedPath.substring(normalizedHome.length + 1).split('/').where((p) => p.isNotEmpty);
    final crumbs = [_BreadcrumbPart(homeLabel, normalizedHome)];
    var current = normalizedHome;
    for (final part in relativeParts) {
      current = current == '/' ? '/$part' : '$current/$part';
      crumbs.add(_BreadcrumbPart(part, current));
    }
    return crumbs;
  }

  String _normalizePath(String value) {
    if (value.isEmpty) return '/';
    var normalized = value;
    if (!normalized.startsWith('/')) normalized = '/$normalized';
    while (normalized.length > 1 && normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }
}

class _BreadcrumbPart {
  final String label;
  final String path;

  const _BreadcrumbPart(this.label, this.path);
}

class FilePreviewScreen extends StatefulWidget {
  final FileExplorerController controller;
  final FileEntry entry;
  final String path;
  final String? openAs;
  final List<FileEntry>? galleryEntries;
  final int galleryIndex;
  final String Function(FileEntry)? pathBuilder;

  const FilePreviewScreen({
    super.key,
    required this.controller,
    required this.entry,
    required this.path,
    this.openAs,
    this.galleryEntries,
    this.galleryIndex = 0,
    this.pathBuilder,
  });

  @override
  State<FilePreviewScreen> createState() => _FilePreviewScreenState();
}

class _FilePreviewScreenState extends State<FilePreviewScreen> {
  late final List<FileEntry> _entries = widget.galleryEntries != null
      ? List.of(widget.galleryEntries!)
      : [widget.entry];
  late int _currentIndex = widget.galleryEntries != null ? widget.galleryIndex : 0;
  late final PageController _pageController = PageController(initialPage: _currentIndex);
  bool _isSaving = false;
  bool _isEditing = false;
  bool _isSharing = false;
  bool _contentChanged = false;

  FileEntry get _currentEntry => _entries[_currentIndex];

  String _pathFor(FileEntry entry) => widget.pathBuilder?.call(entry) ?? widget.path;

  bool get _canEditCurrent {
    final entry = _currentEntry;
    final effectiveName = entry.isSymlink && entry.symlinkTarget != null
        ? entry.symlinkTarget!.split('/').last
        : entry.name;
    final ext = effectiveName.contains('.') ? effectiveName.split('.').last.toLowerCase() : '';
    return kImageExts.contains(ext) && ext != 'svg';
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _share() async {
    if (_isSharing) return;
    setState(() => _isSharing = true);
    final entry = _currentEntry;
    try {
      final bytes = await widget.controller.read(_pathFor(entry));
      await shareFileBytes(entry.name, bytes);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Share failed: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isSharing = false);
    }
  }

  Future<void> _download() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    final entry = _currentEntry;
    try {
      final bytes = await widget.controller.read(_pathFor(entry));
      final savedPath = await saveToDevice(entry.name, bytes);
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

  void _showInfo() {
    _showFileProperties(context, _currentEntry);
  }

  Future<void> _editImage() async {
    if (_isEditing) return;
    final entry = _currentEntry;
    setState(() => _isEditing = true);
    try {
      final bytes = await widget.controller.read(_pathFor(entry));
      if (!mounted) return;
      final edited = await Navigator.push<Uint8List>(
        context,
        MaterialPageRoute(builder: (_) => ImageEditorScreen(bytes: bytes)),
      );
      if (mounted) setState(() => _isEditing = false);
      if (edited == null || !mounted) return;
      await _saveEditedImage(entry, edited);
    } catch (e) {
      if (mounted) {
        setState(() => _isEditing = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Edit failed: $e'), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _saveEditedImage(FileEntry entry, Uint8List bytes) async {
    final target = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Save edited photo'),
        children: [
          SimpleDialogOption(onPressed: () => Navigator.pop(context, 'phone'), child: const Text('Save to phone')),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'replace'),
            child: const Text('Replace original on desktop'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'copy'),
            child: const Text('Save as copy on desktop'),
          ),
        ],
      ),
    );
    if (target == null || !mounted) return;

    if (target == 'phone') {
      try {
        final savedPath = await saveToDevice(entry.name, bytes);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Saved: $savedPath')));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Save failed: $e'), backgroundColor: Colors.red));
        }
      }
      return;
    }

    final path = _pathFor(entry);
    final dir = path.contains('/') ? path.substring(0, path.lastIndexOf('/')) : '';
    final name = entry.name;
    final dot = name.lastIndexOf('.');
    final remoteName = target == 'copy'
        ? (dot > 0 ? '${name.substring(0, dot)}_edited${name.substring(dot)}' : '${name}_edited')
        : name;

    try {
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/$remoteName');
      await tempFile.writeAsBytes(bytes);
      await widget.controller.upload(tempFile.path, dir.isEmpty ? '/' : dir);
      tempFile.delete().catchError((Object _) => tempFile);
      _contentChanged = true;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved to desktop')));
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Save failed: $e'), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _delete() async {
    final entry = _currentEntry;
    if (!await _confirmDelete(context, entry.name)) return;
    try {
      await widget.controller.delete(_pathFor(entry));
      _contentChanged = true;
      if (!mounted) return;
      if (_entries.length <= 1) {
        Navigator.pop(context, true);
        return;
      }
      final removedIndex = _currentIndex;
      setState(() {
        _entries.removeAt(removedIndex);
        _currentIndex = removedIndex >= _entries.length ? _entries.length - 1 : removedIndex;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _pageController.jumpToPage(_currentIndex);
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Delete failed: $e'), backgroundColor: Colors.red));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        Navigator.pop(context, _contentChanged);
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          title: Text(_currentEntry.name, style: const TextStyle(fontSize: 14), overflow: TextOverflow.ellipsis),
          backgroundColor: const Color(0xFF1E1E1E),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        body: _entries.length > 1
            ? PageView.builder(
                controller: _pageController,
                itemCount: _entries.length,
                onPageChanged: (i) => setState(() => _currentIndex = i),
                itemBuilder: (context, i) {
                  final entry = _entries[i];
                  return _PreviewBody(controller: widget.controller, entry: entry, path: _pathFor(entry));
                },
              )
            : _PreviewBody(
                controller: widget.controller,
                entry: widget.entry,
                path: widget.path,
                openAs: widget.openAs,
              ),
        bottomNavigationBar: _GalleryActionBar(
          isSaving: _isSaving,
          isEditing: _isEditing,
          isSharing: _isSharing,
          canEdit: _canEditCurrent,
          onShare: _share,
          onInfo: _showInfo,
          onEdit: _editImage,
          onDownload: _download,
          onDelete: _delete,
        ),
      ),
    );
  }
}

class _GalleryActionBar extends StatelessWidget {
  final bool isSaving;
  final bool isEditing;
  final bool isSharing;
  final bool canEdit;
  final VoidCallback onShare;
  final VoidCallback onInfo;
  final VoidCallback onEdit;
  final VoidCallback onDownload;
  final VoidCallback onDelete;

  const _GalleryActionBar({
    required this.isSaving,
    required this.isEditing,
    required this.isSharing,
    required this.canEdit,
    required this.onShare,
    required this.onInfo,
    required this.onEdit,
    required this.onDownload,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF1E1E1E),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              isSharing
                  ? const _ActionBarButton(icon: Icons.share_outlined, label: 'Sharing…', onTap: null, loading: true)
                  : _ActionBarButton(icon: Icons.share_outlined, label: 'Share', onTap: onShare),
              _ActionBarButton(icon: Icons.info_outline, label: 'Info', onTap: onInfo),
              if (canEdit)
                isEditing
                    ? const _ActionBarButton(icon: Icons.tune, label: 'Editing…', onTap: null, loading: true)
                    : _ActionBarButton(icon: Icons.tune, label: 'Edit', onTap: onEdit),
              isSaving
                  ? const _ActionBarButton(icon: Icons.download_outlined, label: 'Saving…', onTap: null, loading: true)
                  : _ActionBarButton(icon: Icons.download_outlined, label: 'Download', onTap: onDownload),
              _ActionBarButton(icon: Icons.delete_outline, label: 'Delete', onTap: onDelete, color: Colors.redAccent),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionBarButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color color;
  final bool loading;

  const _ActionBarButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color = Colors.white,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            loading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70),
                  )
                : Icon(icon, color: color, size: 22),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(color: color, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

class _PreviewBody extends StatefulWidget {
  final FileExplorerController controller;
  final FileEntry entry;
  final String path;
  final String? openAs;

  const _PreviewBody({required this.controller, required this.entry, required this.path, this.openAs});

  @override
  State<_PreviewBody> createState() => _PreviewBodyState();
}

class _PreviewBodyState extends State<_PreviewBody> {
  Future<Uint8List>? _contentFuture;
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

  String get _ext {
    final effectiveName = widget.entry.isSymlink && widget.entry.symlinkTarget != null
        ? widget.entry.symlinkTarget!.split('/').last
        : widget.entry.name;
    return effectiveName.contains('.') ? effectiveName.split('.').last.toLowerCase() : '';
  }

  Color get _bgColor {
    final effectiveExt = widget.openAs ?? _ext;
    if (effectiveExt == 'pdf') return Colors.grey.shade200;
    return Colors.black;
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _bgColor,
      child: _streamMedia
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
      if (mode == 'image') {
        return InteractiveViewer(
          minScale: 1,
          maxScale: 5,
          child: SizedBox.expand(child: Image.memory(data, fit: BoxFit.contain)),
        );
      }
      if (mode == 'pdf') return _PdfPreview(data: data);
    }

    if (kImageExts.contains(ext)) {
      return InteractiveViewer(
        minScale: 1,
        maxScale: 5,
        child: SizedBox.expand(child: Image.memory(data, fit: BoxFit.contain)),
      );
    }
    if (ext == 'svg') {
      return InteractiveViewer(
        minScale: 1,
        maxScale: 5,
        child: SizedBox.expand(child: SvgPicture.memory(data, fit: BoxFit.contain)),
      );
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
  final bool selectionMode;
  final bool selected;

  const _FileEntryGrid({
    required this.entry,
    required this.onTap,
    required this.onLongPress,
    this.highlight,
    this.selectionMode = false,
    this.selected = false,
  });

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
      child: Container(
        color: selected ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.12) : null,
        child: Stack(
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _FileEntryVisual(entry: entry, ext: ext, size: 56, iconSize: 44),
                const SizedBox(height: 4),
                Padding(padding: const EdgeInsets.symmetric(horizontal: 2), child: nameWidget),
              ],
            ),
            if (selectionMode)
              Positioned(
                top: 2,
                right: 2,
                child: Icon(
                  selected ? Icons.check_circle : Icons.radio_button_unchecked,
                  size: 18,
                  color: selected ? Theme.of(context).colorScheme.primary : Colors.grey,
                ),
              ),
          ],
        ),
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
  final bool selectionMode;
  final bool selected;

  const _FileEntryTile({
    required this.entry,
    required this.onTap,
    required this.onLongPress,
    this.highlight,
    this.selectionMode = false,
    this.selected = false,
  });

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
      leading: selectionMode
          ? Checkbox(value: selected, onChanged: (_) => onTap())
          : _FileEntryVisual(entry: entry, ext: ext, size: 40, iconSize: 34),
      title: _buildTitle(context),
      subtitle: subtitle,
      selected: selectionMode && selected,
      onTap: onTap,
      onLongPress: onLongPress,
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

class _MediaGalleryTile extends StatelessWidget {
  final FileEntry entry;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final bool selectionMode;
  final bool selected;

  const _MediaGalleryTile({
    required this.entry,
    required this.onTap,
    required this.onLongPress,
    this.selectionMode = false,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveName = entry.isSymlink && entry.symlinkTarget != null
        ? entry.symlinkTarget!.split('/').last
        : entry.name;
    final ext = effectiveName.contains('.') ? effectiveName.split('.').last.toLowerCase() : '';
    final isVideo = kVideoExts.contains(ext);
    final thumbnail = _decodeThumbnail(entry.thumbnail);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: ColoredBox(
        color: isDark ? const Color(0xFF111827) : const Color(0xFFE2E8F0),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (thumbnail != null)
              Image.memory(thumbnail, fit: BoxFit.cover, gaplessPlayback: true)
            else
              Center(
                child: Icon(
                  isVideo ? Icons.movie_outlined : Icons.image_outlined,
                  size: 32,
                  color: isDark ? Colors.white24 : Colors.black26,
                ),
              ),
            if (isVideo)
              const Positioned(
                right: 4,
                bottom: 4,
                child: Icon(
                  Icons.play_circle_fill,
                  color: Colors.white,
                  size: 22,
                  shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
                ),
              ),
            if (selected) ColoredBox(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.35)),
            if (selectionMode)
              Positioned(
                top: 4,
                right: 4,
                child: Icon(
                  selected ? Icons.check_circle : Icons.radio_button_unchecked,
                  size: 20,
                  color: selected ? Colors.white : Colors.white70,
                  shadows: const [Shadow(color: Colors.black54, blurRadius: 4)],
                ),
              ),
          ],
        ),
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
