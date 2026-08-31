import 'dart:async';

import 'package:flutter/foundation.dart';

class OtpResendCooldown {
  OtpResendCooldown({this.duration = const Duration(minutes: 1)}) : _secondsRemaining = duration.inSeconds;

  final Duration duration;
  Timer? _timer;
  int _secondsRemaining;

  bool get canResend => _secondsRemaining == 0;

  String get label {
    if (_secondsRemaining == 0) return 'Resend code';

    final minutes = _secondsRemaining ~/ 60;
    final seconds = (_secondsRemaining % 60).toString().padLeft(2, '0');
    return 'Resend code in $minutes:$seconds';
  }

  void start({required VoidCallback onChanged, bool notifyImmediately = true}) {
    _timer?.cancel();
    _secondsRemaining = duration.inSeconds;

    if (notifyImmediately) onChanged();

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsRemaining <= 1) {
        timer.cancel();
        _secondsRemaining = 0;
      } else {
        _secondsRemaining--;
      }

      onChanged();
    });
  }

  void dispose() {
    _timer?.cancel();
  }
}
