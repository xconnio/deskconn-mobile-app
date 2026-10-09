import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

Terminal _terminal() => Terminal(maxLines: 1000)..resize(80, 24);

void _feedShortRegion(Terminal terminal) {
  terminal.write('\x1b[1;10r');
  terminal.write('\x1b[10;1H');
  for (var i = 0; i < 30; i++) {
    terminal.write('line $i\n');
  }
}

void main() {
  test('line feed after scrolling a top-margined region does not crash', () {
    final terminal = _terminal();

    terminal.write('\x1b[5;24r');
    terminal.write('\x1b[24;1H');
    for (var i = 0; i < 5; i++) {
      terminal.write('scroll $i\n');
    }

    _feedShortRegion(terminal);
  });

  test('line feed after deleting lines in a region does not crash', () {
    final terminal = _terminal();

    terminal.write('\x1b[5;24r');
    terminal.write('\x1b[5;1H');
    terminal.write('\x1b[3M');

    _feedShortRegion(terminal);
  });

  test('scroll regions keep working after clearing scrollback', () {
    final terminal = _terminal();

    terminal.write('\x1b[r');
    for (var i = 0; i < 1200; i++) {
      terminal.write('history $i\n');
    }
    terminal.write('\x1b[3J');

    terminal.write('\x1b[5;24r');
    terminal.write('\x1b[24;1H');
    for (var i = 0; i < 5; i++) {
      terminal.write('scroll $i\n');
    }

    _feedShortRegion(terminal);
  });
}
