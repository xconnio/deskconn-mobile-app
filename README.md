# Deskconn Mobile App

Connect to your desk and control it remotely.

## Features


- **Terminal** — open a shell session on your desktop from your phone
- **File explorer** — browse, share, and download files from your desktop
-  **Remote control** — lock/unlock the screen, adjust brightness, control
    media playback (MPRIS) with track artwork, mute/unmute audio, take
    screenshots
- **Share to desktop** — send files/photos from your phone to your desktop
- **Account & device management** — sign up/sign in, manage your account,
  and manage the devices paired to it

## Setup

```
flutter pub get
```

The app talks to desktops over a QUIC transport (`lib/core/wamp/quic_library_path.dart`).
Without the platform's native QUIC library, it silently falls back to the
router's WebSocket endpoint instead — so if desktop connections feel slow or
flaky, check this first. Build/fetch it per platform:

### Android

```
make setup-quic
```

Downloads a prebuilt `.so` into `android/app/src/main/jniLibs/arm64-v8a/`. No
Rust toolchain needed.

### iOS

```
make setup-quic-ios
```

Requires the Rust toolchain (`rustup`) with the `aarch64-apple-ios` and
`aarch64-apple-ios-sim` targets, run from a shell with `git`/`sed`/`cargo`
available (macOS Terminal is fine). Builds static libs into
`ios/Runner/QuicFFI/`.

### Windows

Requires **Git for Windows** (the recipe does `git clone`/`sed`, and its
bundled `bash.exe` is what runs the recipe — see below), plus two things not
needed on other platforms since `cargo build` compiles the crate locally
here:

1. **Rust toolchain** (`rustup` + `cargo`):
   ```
   winget install Rustlang.Rustup
   ```
   Restart your terminal afterwards so `cargo`/`rustc` are on `PATH`.

2. **MSVC linker** (`link.exe`) — the default `x86_64-pc-windows-msvc` Rust
   target needs it to link the DLL. Install Visual Studio Build Tools with
   the C++ workload:
   ```
   winget install --id Microsoft.VisualStudio.2022.BuildTools -e --override "--wait --passive --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"
   ```
   (Skip if you already have Visual Studio with "Desktop development with
   C++".) This is a multi-GB download and can take several minutes.

Then, from **any** shell (PowerShell, cmd, or Git Bash):
```
make setup-quic-windows
```
The Makefile forces this recipe through Git Bash's `bash.exe` on Windows,
since the recipe is a POSIX shell script and Windows `make` otherwise
defaults to `cmd.exe`, which can't parse it — but only if it finds
`C:/Program Files/Git/bin/bash.exe` (Git for Windows' default install
location); other targets (`install`, `lint`, etc.) still work via `cmd.exe`
either way. If your Git install lives elsewhere, run `make setup-quic-windows`
directly from a Git Bash terminal instead, where `make`'s own shell
detection picks up `bash` correctly.

Builds `windows/native/dart_quic_ffi.dll`, which gets bundled next to the
`.exe` automatically by `windows/CMakeLists.txt` on the next `flutter run`/
`flutter build windows`.

#### Known build issues with newer CMake / Visual Studio

If your CMake is 4.0+ (bundled with recent Visual Studio installs — check
with `cmake --version`), `flutter run -d windows` / `flutter build windows`
can fail for reasons unrelated to this app's own code, since several
dependencies (Firebase, pdfx's bundled `pdfium` downloader) still declare
very old `cmake_minimum_required` versions that CMake 4.x refuses outright:

1. **`CMake Error ... Compatibility with CMake < 3.5 has been removed`**
   for `firebase_cpp_sdk_windows` or similar — set an environment variable
   (persists across terminals) and restart your terminal:
   ```
   setx CMAKE_POLICY_VERSION_MINIMUM 3.5
   ```

2. **Same error but for `pdfium` / `DownloadProject.cmake` failing** — the
   env var above doesn't reach this one (it configures `pdfium` as a
   separate nested `cmake` invocation at configure time). Patch the
   template directly in your pub cache:
   ```
   sed -i "s/VERSION 2.8.12/VERSION 3.5/" "$(dirname "$(find "$LOCALAPPDATA/Pub/Cache" -path '*pdfx-*/windows/DownloadProject.CMakeLists.cmake.in' 2>/dev/null | head -1)")/DownloadProject.CMakeLists.cmake.in"
   ```
   (Run from Git Bash. This needs re-applying if you ever wipe/reinstall
   your pub cache or bump the `pdfx` package version — it isn't something
   this repo can fix, since the file lives in the package's own source.)

3. **`error C2338: ... /await compiler option ... deprecated'** while
   building `audioplayers_windows` — a very recent MSVC toolset turns this
   from a warning into a hard error. Silence it via the `_CL_` env var
   (also read automatically by `cl.exe`; persists across terminals):
   ```
   setx _CL_ "/D_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS"
   ```

Both `setx` commands only affect *new* terminal sessions — open a fresh one
(or restart your IDE) before retrying the build.

### Linux

Nothing to do — `linux/native/libdart_quic_ffi.so` is committed to the repo
and gets installed next to the executable by `linux/runner/CMakeLists.txt`
automatically.

### macOS

Not yet automated (no Makefile target, no bundling step in the Xcode
project). The app will fall back to the WebSocket endpoint on macOS until
this is added.

