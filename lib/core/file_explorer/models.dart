class FileEntry {
  final String name;
  final bool isDir;
  final int size;
  final int mtime;
  final int mode;
  final bool isSymlink;
  final String? symlinkTarget;

  FileEntry({
    required this.name,
    required this.isDir,
    required this.size,
    required this.mtime,
    required this.mode,
    required this.isSymlink,
    this.symlinkTarget,
  });

  factory FileEntry.fromJson(Map<String, dynamic> json) {
    return FileEntry(
      name: (json['name'] as String?) ?? '',
      isDir: _toBool(json['is_dir']),
      size: _toInt(json['size']),
      mtime: _toInt(json['mtime']),
      mode: _toInt(json['mode']),
      isSymlink: _toBool(json['is_symlink']),
      symlinkTarget: json['symlink_target'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'is_dir': isDir,
    'size': size,
    'mtime': mtime,
    'mode': mode,
    'is_symlink': isSymlink,
    'symlink_target': symlinkTarget,
  };
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

  FileBrowseResult({required this.path, required this.homePath, required this.entries});

  factory FileBrowseResult.fromJson(Map<String, dynamic> json) {
    return FileBrowseResult(
      path: (json['path'] as String?) ?? '/',
      homePath: (json['home_path'] as String?) ?? '/',
      entries:
          (json['entries'] as List<dynamic>?)?.map((e) => FileEntry.fromJson(Map<String, dynamic>.from(e))).toList() ??
          [],
    );
  }
}
