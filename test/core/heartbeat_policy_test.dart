import 'package:deskconn_mobile_app/core/wamp/desktop_connection_manager.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  bool drop({bool strict = false, bool connected = true, required int misses}) =>
      DesktopConnectionManager.shouldDropAfterHeartbeatFailure(strict: strict, connected: connected, misses: misses);

  group('routine heartbeat on a live session', () {
    test('a single slow reply keeps the connection', () => expect(drop(misses: 1), isFalse));

    test('two misses in a row still keep the connection', () => expect(drop(misses: 2), isFalse));

    test('the third consecutive miss drops the connection', () {
      expect(drop(misses: DesktopConnectionManager.heartbeatMaxMisses), isTrue);
    });

    test('misses beyond the limit keep dropping', () => expect(drop(misses: 10), isTrue));

    test('every miss count below the limit is tolerated', () {
      for (var m = 1; m < DesktopConnectionManager.heartbeatMaxMisses; m++) {
        expect(drop(misses: m), isFalse, reason: 'misses=$m');
      }
    });
  });

  group('session already disconnected', () {
    test('drops on the very first failure', () => expect(drop(connected: false, misses: 1), isTrue));

    test('drops regardless of miss count', () {
      for (var m = 1; m <= 5; m++) {
        expect(drop(connected: false, misses: m), isTrue, reason: 'misses=$m');
      }
    });
  });

  group('verification after a network change', () {
    test('a failed check drops immediately even on a live session', () {
      expect(drop(strict: true, misses: 1), isTrue);
    });

    test('a failed check drops a disconnected session', () {
      expect(drop(strict: true, connected: false, misses: 1), isTrue);
    });
  });

  test('the miss limit tolerates at least one extra slow reply', () {
    expect(DesktopConnectionManager.heartbeatMaxMisses, greaterThanOrEqualTo(2));
  });

  test('every combination follows the rule strict or disconnected or limit reached', () {
    for (final strict in [false, true]) {
      for (final connected in [false, true]) {
        for (var misses = 1; misses <= 6; misses++) {
          final expected = strict || !connected || misses >= DesktopConnectionManager.heartbeatMaxMisses;
          expect(
            drop(strict: strict, connected: connected, misses: misses),
            expected,
            reason: 'strict=$strict connected=$connected misses=$misses',
          );
        }
      }
    }
  });
}
