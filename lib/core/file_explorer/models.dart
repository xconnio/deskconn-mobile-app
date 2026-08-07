class FileEntry {
  final String name;
  final String path;
  final bool isDir;
  final int size;
  final int mtime;
  final int mode;
  final bool isSymlink;
  final String? symlinkTarget;
  final String? thumbnail;

  FileEntry({
    required this.name,
    required this.path,
    required this.isDir,
    required this.size,
    required this.mtime,
    required this.mode,
    required this.isSymlink,
    this.symlinkTarget,
    this.thumbnail,
  });

  factory FileEntry.fromJson(Map<String, dynamic> json) {
    return FileEntry(
      name: (json['name'] as String?) ?? '',
      path: (json['path'] as String?) ?? '',
      isDir: _toBool(json['is_dir']),
      size: _toInt(json['size']),
      mtime: _toMtime(json['mtime'] ?? json['mod_time']),
      mode: _toInt(json['mode']),
      isSymlink: _toBool(json['is_symlink']),
      symlinkTarget: (json['symlink_target'] ?? json['link_target']) as String?,
      thumbnail: json['thumbnail'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'path': path,
    'is_dir': isDir,
    'size': size,
    'mtime': mtime,
    'mode': mode,
    'is_symlink': isSymlink,
    'symlink_target': symlinkTarget,
    'thumbnail': thumbnail,
  };
}

int _toMtime(dynamic value) {
  if (value == null) return 0;
  if (value is int) return value;
  if (value is double) return value.toInt();
  if (value is String) {
    final asInt = int.tryParse(value);
    if (asInt != null) return asInt;
    final parsed = DateTime.tryParse(value);
    if (parsed != null) return parsed.millisecondsSinceEpoch ~/ 1000;
  }
  return 0;
}

int _toInt(dynamic value) {
  if (value == null) return 0;
  if (value is int) return value;
  if (value is String) return int.tryParse(value) ?? 0;
  if (value is double) return value.toInt();
  return 0;
}

bool _toBool(dynamic value) {
  if (value == null) return false;
  if (value is bool) return value;
  if (value is int) return value != 0;
  if (value is String) return value.toLowerCase() == 'true' || value == '1';
  return false;
}

class FileBrowseResult {
  final String path;
  final String homePath;
  final List<FileEntry> entries;
  final String? nextCursor;
  final bool hasMore;

  FileBrowseResult({
    required this.path,
    required this.homePath,
    required this.entries,
    this.nextCursor,
    this.hasMore = false,
  });

  factory FileBrowseResult.fromJson(Map<String, dynamic> json) {
    return FileBrowseResult(
      path: (json['path'] as String?) ?? '/',
      homePath: (json['home_path'] as String?) ?? '/',
      entries:
          (json['entries'] as List<dynamic>?)?.map((e) => FileEntry.fromJson(Map<String, dynamic>.from(e))).toList() ??
          [],
      nextCursor: json['next_cursor'] as String?,
      hasMore: _toBool(json['has_more']),
    );
  }
}
