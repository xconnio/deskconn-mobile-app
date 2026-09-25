import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:xterm/core.dart';
// ignore: implementation_imports
import 'package:xterm/src/ui/painter.dart';
import 'package:xterm/ui.dart';

import 'terminal_links.dart';
import 'terminal_theme.dart';

class TerminalLinkRepaint extends ChangeNotifier {
  TerminalLinkRepaint(Terminal terminal) : _terminal = terminal {
    _terminal.addListener(_onTerminalChanged);
  }

  final Terminal _terminal;

  void _onTerminalChanged() => notifyListeners();

  @override
  void dispose() {
    _terminal.removeListener(_onTerminalChanged);
    super.dispose();
  }
}

class TerminalLinkPainter extends CustomPainter {
  TerminalLinkPainter({
    required this.terminal,
    required TerminalTheme theme,
    required TerminalStyle textStyle,
    required TextScaler textScaler,
    required this.resolveOrigin,
    required Listenable repaint,
  }) : painter = TerminalPainter(theme: theme, textStyle: textStyle, textScaler: textScaler),
       super(repaint: repaint);

  final Terminal terminal;
  final TerminalPainter painter;
  final Offset? Function() resolveOrigin;

  static final CursorStyle _linkStyle = CursorStyle()
    ..setForegroundColorRgb(kTerminalAccentR, kTerminalAccentG, kTerminalAccentB)
    ..setUnderline();

  @override
  bool? hitTest(Offset position) => false;

  @override
  void paint(Canvas canvas, Size size) {
    final origin = resolveOrigin();
    if (origin == null) return;

    final cell = painter.cellSize;
    if (cell.height <= 0 || cell.width <= 0) return;

    final lines = terminal.buffer.lines;
    if (lines.length == 0) return;

    final firstRow = math.max(0, ((-origin.dy) / cell.height).floor());
    final lastRow = math.min(lines.length - 1, ((size.height - origin.dy) / cell.height).ceil());
    if (lastRow < firstRow) return;

    final cells = TerminalLinks.linkCells(terminal, firstRow, lastRow);
    if (cells.isEmpty) return;

    final byRow = <int, List<int>>{};
    for (final cellOffset in cells) {
      (byRow[cellOffset.y] ??= <int>[]).add(cellOffset.x);
    }

    for (final entry in byRow.entries) {
      final row = entry.key;
      if (row < firstRow || row > lastRow) continue;

      final source = lines[row];
      final line = BufferLine(terminal.viewWidth);
      var hasContent = false;
      for (final col in entry.value) {
        final codePoint = source.getCodePoint(col);
        if (codePoint == 0) continue;
        line.setCell(col, codePoint, source.getWidth(col), _linkStyle);
        hasContent = true;
      }
      if (!hasContent) continue;

      painter.paintLine(canvas, Offset(origin.dx, origin.dy + row * cell.height), line);
    }
  }

  @override
  bool shouldRepaint(covariant TerminalLinkPainter oldDelegate) => true;
}
