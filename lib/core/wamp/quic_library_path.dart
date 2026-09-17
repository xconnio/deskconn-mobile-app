import 'dart:io';

import 'package:flutter/foundation.dart';

/// dart_quic's default loader does a bare-name `dlopen`/`LoadLibrary`, which
/// depends on OS/rpath search rules we don't control. On desktop we instead
/// bundle the native library next to the executable (see
/// linux/CMakeLists.txt) and point xconn's `QUICDialerConfig.libraryPath` at
/// it directly. Android (jniLibs) and iOS (statically linked) already work
/// without this, so this only returns a path on desktop platforms.
String? desktopQuicLibraryPath() {
  if (kIsWeb) return null;

  final executableDir = File(Platform.resolvedExecutable).parent.path;
  if (Platform.isLinux) return '$executableDir/libdart_quic_ffi.so';
  if (Platform.isWindows) return '$executableDir\\dart_quic_ffi.dll';
  if (Platform.isMacOS) return '$executableDir/libdart_quic_ffi.dylib';
  return null;
}

/// Whether QUIC can actually be dialled here: on mobile the library is linked
/// into the app, on desktop it has to be bundled next to the executable.
bool get hasDesktopQuicLibrary {
  if (kIsWeb) return false;
  if (!Platform.isLinux && !Platform.isWindows && !Platform.isMacOS) return true;

  final path = desktopQuicLibraryPath();
  return path != null && File(path).existsSync();
}
