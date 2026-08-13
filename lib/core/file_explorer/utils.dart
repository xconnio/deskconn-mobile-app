import 'dart:math' as math;
import 'package:deskconn_mobile_app/theme/colors.dart';
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

bool isPreviewSupported(String ext) =>
    kImageExts.contains(ext) ||
    kTextExts.contains(ext) ||
    kVideoExts.contains(ext) ||
    kAudioExts.contains(ext) ||
    ext == 'pdf';

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
// by color at a glance, not just by icon shape. Resolved via the active
// palette so light/dark stay coherent with the app theme.
Color? getFileIconColor(String ext, DeskconnPalette palette) {
  if (kImageExts.contains(ext)) return palette.typeImage;
  if (kVideoExts.contains(ext)) return palette.typeVideo;
  if (kAudioExts.contains(ext)) return palette.typeAudio;
  if (kWordExts.contains(ext)) return palette.typeWord;
  if (kExcelExts.contains(ext)) return palette.typeExcel;
  if (kPowerPointExts.contains(ext)) return palette.typePowerPoint;
  if (kTextExts.contains(ext)) return palette.typeText;
  if (kArchiveExts.contains(ext)) return palette.typeArchive;
  switch (ext) {
    case 'pdf':
      return palette.typePdf;
    case 'apk':
      return palette.typeExecutable;
    case 'exe':
    case 'msi':
    case 'dmg':
      return palette.typeExecutable;
    case 'db':
    case 'sqlite':
    case 'sqlite3':
      return palette.typeExecutable;
    default:
      return palette.typeDefault;
  }
}
