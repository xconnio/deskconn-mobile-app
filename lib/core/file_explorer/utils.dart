import 'dart:math' as math;
import 'package:flutter/material.dart';

const kImageExts = {'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'ico', 'svg'};
const kTextExts = {
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
  'csv',
  'vue',
  'svelte',
};
const kVideoExts = {'mp4', 'mkv', 'avi', 'mov', 'webm', 'flv', 'm4v', 'wmv', '3gp', 'ogv'};
const kAudioExts = {'mp3', 'wav', 'ogg', 'flac', 'aac', 'm4a', 'wma', 'opus'};

String formatSize(int bytes) {
  if (bytes <= 0) return "0 B";
  const suffixes = ["B", "KB", "MB", "GB", "TB"];
  var i = (math.log(bytes) / math.log(1024)).floor();
  return "${(bytes / math.pow(1024, i)).toStringAsFixed(i > 0 ? 1 : 0)} ${suffixes[i]}";
}

const kWordExts = {'doc', 'docx', 'odt', 'rtf'};
const kExcelExts = {'xls', 'xlsx', 'ods'};
const kPowerPointExts = {'ppt', 'pptx', 'odp'};
const kArchiveExts = {'zip', 'rar', '7z', 'tar', 'gz', 'xz', 'bz2'};

IconData getFileIcon(String ext) {
  if (kImageExts.contains(ext)) return Icons.image;
  if (kVideoExts.contains(ext)) return Icons.movie;
  if (kAudioExts.contains(ext)) return Icons.audiotrack;
  if (kWordExts.contains(ext)) return Icons.description;
  if (kExcelExts.contains(ext)) return Icons.table_chart;
  if (kPowerPointExts.contains(ext)) return Icons.slideshow;
  if (kTextExts.contains(ext)) return Icons.code;
  if (kArchiveExts.contains(ext)) return Icons.folder_zip;
  switch (ext) {
    case 'pdf':
      return Icons.picture_as_pdf;
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

// Mirrors the color-by-type convention of most desktop/mobile file managers
// (Windows Explorer, Files by Google, etc.) so file types are recognizable
// by color at a glance, not just by icon shape.
Color? getFileIconColor(String ext, {required bool isDark}) {
  if (kImageExts.contains(ext)) {
    return isDark ? const Color(0xFFC4B5FD) : const Color(0xFF7C3AED);
  }
  if (kVideoExts.contains(ext)) {
    return isDark ? const Color(0xFFFDA4AF) : const Color(0xFFE11D48);
  }
  if (kAudioExts.contains(ext)) {
    return isDark ? const Color(0xFFF9A8D4) : const Color(0xFFDB2777);
  }
  if (kWordExts.contains(ext)) {
    return isDark ? const Color(0xFF93C5FD) : const Color(0xFF2563EB);
  }
  if (kExcelExts.contains(ext)) {
    return isDark ? const Color(0xFF86EFAC) : const Color(0xFF16A34A);
  }
  if (kPowerPointExts.contains(ext)) {
    return isDark ? const Color(0xFFFDBA74) : const Color(0xFFEA580C);
  }
  if (kTextExts.contains(ext)) {
    return isDark ? const Color(0xFF5EEAD4) : const Color(0xFF0D9488);
  }
  if (kArchiveExts.contains(ext)) {
    return isDark ? const Color(0xFFFCD34D) : const Color(0xFFB45309);
  }
  switch (ext) {
    case 'pdf':
      return isDark ? const Color(0xFFFCA5A5) : const Color(0xFFDC2626);
    case 'apk':
      return isDark ? const Color(0xFF86EFAC) : const Color(0xFF16A34A);
    case 'exe':
    case 'msi':
    case 'dmg':
      return isDark ? const Color(0xFFA5B4FC) : const Color(0xFF4F46E5);
    case 'db':
    case 'sqlite':
    case 'sqlite3':
      return isDark ? const Color(0xFFA5B4FC) : const Color(0xFF4F46E5);
    default:
      return isDark ? const Color(0xFFCBD5E1) : null;
  }
}
