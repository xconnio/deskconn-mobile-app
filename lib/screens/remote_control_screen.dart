import 'dart:convert';
import 'dart:typed_data';

import 'package:deskconn_mobile_app/core/constants.dart';
import 'package:deskconn_mobile_app/core/terminal/terminal_background_service.dart';
import 'package:deskconn_mobile_app/core/wamp/desktop_connection_manager.dart';
import 'package:deskconn_mobile_app/screens/file_explorer_screen.dart' show saveToDevice;
import 'package:flutter/material.dart';
import 'package:xconn/xconn.dart';

const _procLock = 'io.xconn.deskconn.deskconnd.screen.lock';
const _procBrightnessGet = 'io.xconn.deskconn.deskconnd.screen.brightness.get';
const _procBrightnessSet = 'io.xconn.deskconn.deskconnd.screen.brightness.set';
const _procMprisPlayers = 'io.xconn.deskconn.deskconnd.mpris.players';
const _procMprisPlayPause = 'io.xconn.deskconn.deskconnd.mpris.playpause';
const _procMprisPrev = 'io.xconn.deskconn.deskconnd.mpris.previous';
const _procMprisNext = 'io.xconn.deskconn.deskconnd.mpris.next';
const _procAudioIsMuted = 'io.xconn.deskconn.deskconnd.audio.ismuted';
const _procAudioToggleMute = 'io.xconn.deskconn.deskconnd.audio.togglemute';
const _procScreenshot = 'io.xconn.deskconn.deskconnd.screenshot';

class RemoteControlScreen extends StatefulWidget {
  final DesktopSessionLaunchConfig config;

  const RemoteControlScreen({super.key, required this.config});

  @override
  State<RemoteControlScreen> createState() => _RemoteControlScreenState();
}

class _RemoteControlScreenState extends State<RemoteControlScreen> {
  double _brightness = 50;
  bool _brightnessLoaded = false;
  bool _locking = false;
  bool _capturingScreenshot = false;
  bool _isPlaying = false;
  List<String> _playerNames = [];
  bool? _isMuted;

  Session? get _session => DesktopConnectionManager().get(widget.config.realm)?.session;

  // User-initiated actions were previously calling _session?.call(...) and
  // silently doing nothing when the connection was gone — no feedback at
  // all. This routes them through one place that reports the failure.
  Future<void> _run(Future<void> Function(Session session) action) async {
    final session = _session;
    if (session == null) {
      _showOffline();
      return;
    }
    try {
      await action(session);
    } catch (_) {
      if (mounted) _showOffline();
    }
  }

  void _showOffline() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Desktop is offline. Action not sent.')));
  }

  @override
  void initState() {
    super.initState();
    _loadBrightness();
    _loadPlayers();
    _loadMuteState();
  }

  Future<void> _loadBrightness() async {
    final session = _session;
    if (session == null) return;
    try {
      final result = await session.call(_procBrightnessGet).timeout(DeskconnConfig.callTimeout);
      if (mounted && result.args.isNotEmpty) {
        setState(() {
          _brightness = (result.args[0] as num).toDouble().clamp(1, 100);
          _brightnessLoaded = true;
        });
      }
    } catch (_) {}
  }

  Future<void> _loadPlayers() async {
    final session = _session;
    if (session == null) return;
    try {
      final result = await session.call(_procMprisPlayers).timeout(DeskconnConfig.callTimeout);
      if (mounted && result.args.isNotEmpty) {
        final map = result.args[0] as Map;
        setState(() => _playerNames = map.values.map((v) => v.toString()).toList());
      }
    } catch (_) {}
  }

  Future<void> _loadMuteState() async {
    final session = _session;
    if (session == null) return;
    try {
      final result = await session.call(_procAudioIsMuted).timeout(DeskconnConfig.callTimeout);
      if (mounted && result.args.isNotEmpty) {
        setState(() => _isMuted = result.args[0] as bool);
      }
    } catch (_) {}
  }

  Future<void> _toggleMute() async {
    await _run((session) async {
      final result = await session.call(_procAudioToggleMute).timeout(DeskconnConfig.callTimeout);
      if (mounted && result.args.isNotEmpty) {
        setState(() => _isMuted = result.args[0] as bool);
      }
    });
  }

  Future<void> _lockScreen() async {
    if (_locking) return;
    setState(() => _locking = true);
    try {
      await _run((session) => session.call(_procLock).timeout(DeskconnConfig.callTimeout));
    } finally {
      if (mounted) setState(() => _locking = false);
    }
  }

  Future<void> _setBrightness(int percent) async {
    await _run((session) => session.call(_procBrightnessSet, args: [percent]).timeout(DeskconnConfig.callTimeout));
  }

  Future<void> _takeScreenshot() async {
    if (_capturingScreenshot) return;
    final session = _session;
    if (session == null) {
      _showOffline();
      return;
    }
    setState(() => _capturingScreenshot = true);
    try {
      final result = await session.call(_procScreenshot).timeout(DeskconnConfig.callTimeout);
      final bytes = _coerceBytes(result.args[0]);
      if (mounted) {
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => _ScreenshotPreviewScreen(bytes: bytes)));
      }
    } catch (e) {
      if (!mounted) return;
      if (e.toString().toLowerCase().contains('screenshot not enabled')) {
        _showScreenshotDisabledDialog();
      } else {
        _showOffline();
      }
    } finally {
      if (mounted) setState(() => _capturingScreenshot = false);
    }
  }

  void _showScreenshotDisabledDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Screenshot not enabled'),
        content: const Text("Run 'desk screenshot enable' on the desktop to allow remote screenshots."),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
      ),
    );
  }

  Uint8List _coerceBytes(dynamic raw) {
    if (raw is Uint8List) return raw;
    if (raw is List<int>) return Uint8List.fromList(raw);
    if (raw is String) return Uint8List.fromList(base64.decode(raw));
    throw FormatException('Unsupported payload type: ${raw.runtimeType}');
  }

  Future<void> _mprisCall(String proc) async {
    await _run((session) => session.call(proc).timeout(DeskconnConfig.callTimeout));
  }

  Future<void> _togglePlayPause() async {
    setState(() => _isPlaying = !_isPlaying);
    await _mprisCall(_procMprisPlayPause);
  }

  void _showBrightnessSheet() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => _BrightnessSheet(
        initial: _brightness,
        onChanged: (v) {
          if (mounted) setState(() => _brightness = v);
        },
        onChangeEnd: (v) => _setBrightness(v.round()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.config.desktopName)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 4,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            children: [
              _IconTile(
                icon: _locking ? null : Icons.lock_outline,
                label: 'Lock',
                loading: _locking,
                onTap: _lockScreen,
              ),
              _IconTile(
                icon: Icons.brightness_6_outlined,
                label: _brightnessLoaded ? '${_brightness.round()}%' : 'Brightness',
                onTap: _showBrightnessSheet,
              ),
              _IconTile(
                icon: _isMuted == null
                    ? Icons.volume_up_outlined
                    : (_isMuted! ? Icons.volume_off_outlined : Icons.volume_up_outlined),
                label: _isMuted == null ? 'Mute' : (_isMuted! ? 'Muted' : 'Unmuted'),
                onTap: _toggleMute,
              ),
              _IconTile(
                icon: _capturingScreenshot ? null : Icons.photo_camera_outlined,
                label: 'Screenshot',
                loading: _capturingScreenshot,
                onTap: _takeScreenshot,
              ),
            ],
          ),
          const SizedBox(height: 16),
          _MediaCard(
            playerNames: _playerNames,
            isPlaying: _isPlaying,
            onPrev: () => _mprisCall(_procMprisPrev),
            onPlayPause: _togglePlayPause,
            onNext: () => _mprisCall(_procMprisNext),
          ),
        ],
      ),
    );
  }
}

class _IconTile extends StatelessWidget {
  final IconData? icon;
  final String label;
  final VoidCallback onTap;
  final bool loading;

  const _IconTile({required this.label, required this.onTap, this.icon, this.loading = false});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            loading
                ? const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(icon, size: 28, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 6),
            Text(label, style: const TextStyle(fontSize: 11), overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}

class _MediaCard extends StatelessWidget {
  final List<String> playerNames;
  final bool isPlaying;
  final VoidCallback onPrev;
  final VoidCallback onPlayPause;
  final VoidCallback onNext;

  const _MediaCard({
    required this.playerNames,
    required this.isPlaying,
    required this.onPrev,
    required this.onPlayPause,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final playerLabel = playerNames.isEmpty ? 'No active players' : playerNames.join('  ·  ');

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.music_note, size: 16, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    playerLabel,
                    style: Theme.of(context).textTheme.bodySmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(icon: const Icon(Icons.skip_previous_rounded), iconSize: 40, onPressed: onPrev),
                IconButton(
                  icon: Icon(isPlaying ? Icons.pause_circle_outline_rounded : Icons.play_circle_outline_rounded),
                  iconSize: 52,
                  onPressed: onPlayPause,
                ),
                IconButton(icon: const Icon(Icons.skip_next_rounded), iconSize: 40, onPressed: onNext),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BrightnessSheet extends StatefulWidget {
  final double initial;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  const _BrightnessSheet({required this.initial, required this.onChanged, required this.onChangeEnd});

  @override
  State<_BrightnessSheet> createState() => _BrightnessSheetState();
}

class _BrightnessSheetState extends State<_BrightnessSheet> {
  late double _value;

  @override
  void initState() {
    super.initState();
    _value = widget.initial;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.brightness_6_outlined, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 10),
              Text('Brightness  ${_value.round()}%', style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
          const SizedBox(height: 8),
          Slider(
            value: _value,
            min: 1,
            max: 100,
            divisions: 99,
            onChanged: (v) {
              setState(() => _value = v);
              widget.onChanged(v);
            },
            onChangeEnd: widget.onChangeEnd,
          ),
        ],
      ),
    );
  }
}

class _ScreenshotPreviewScreen extends StatefulWidget {
  final Uint8List bytes;

  const _ScreenshotPreviewScreen({required this.bytes});

  @override
  State<_ScreenshotPreviewScreen> createState() => _ScreenshotPreviewScreenState();
}

class _ScreenshotPreviewScreenState extends State<_ScreenshotPreviewScreen> {
  bool _isSaving = false;

  Future<void> _save() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    try {
      final filename = 'screenshot_${DateTime.now().millisecondsSinceEpoch}.png';
      final savedPath = await saveToDevice(filename, widget.bytes);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Saved: $savedPath'), duration: const Duration(seconds: 5)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Save failed: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Screenshot'),
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
              : IconButton(icon: const Icon(Icons.download_outlined), tooltip: 'Save to device', onPressed: _save),
        ],
      ),
      body: Center(child: InteractiveViewer(child: Image.memory(widget.bytes))),
    );
  }
}
