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

IconData getFileIcon(String ext) {
  if (kImageExts.contains(ext)) return Icons.image;
  if (kVideoExts.contains(ext)) return Icons.movie;
  if (kAudioExts.contains(ext)) return Icons.audiotrack;
  if (kTextExts.contains(ext)) return Icons.description;
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

Color? getFileIconColor(String ext, {required bool isDark}) {
  if (kVideoExts.contains(ext)) {
    return isDark ? const Color(0xFF93C5FD) : const Color(0xFF64748B);
  }
  if (kAudioExts.contains(ext)) {
    return isDark ? const Color(0xFFC4B5FD) : const Color(0xFF475569);
  }
  if (kTextExts.contains(ext)) {
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
