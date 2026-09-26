import 'package:xterm/core.dart';

class TerminalLinks {
  TerminalLinks._();

  static final RegExp _pattern = RegExp(r'(?:https?://|ftp://|www\.)[^\s<>"`\[\]{}|\\^]+', caseSensitive: false);

  static const String _trailing = '.,;:!?)]}\'"';

  static String? urlAt(Terminal terminal, CellOffset cell) {
    final buffer = terminal.buffer;
    final lines = buffer.lines;
    if (cell.y < 0 || cell.y >= lines.length) return null;

    var startLine = cell.y;
    while (startLine > 0 && lines[startLine].isWrapped) {
      startLine--;
    }

    final builder = StringBuffer();
    var index = -1;
    for (var line = startLine; line < lines.length; line++) {
      if (line == cell.y) index = builder.length + cell.x;
      builder.write(_lineText(lines[line], buffer.viewWidth));
      if (line + 1 >= lines.length || !lines[line + 1].isWrapped) break;
    }
    if (index < 0) return null;

    final text = builder.toString();
    for (final match in _pattern.allMatches(text)) {
      var end = match.end;
      while (end > match.start && _trailing.contains(text[end - 1])) {
        end--;
      }
      if (index >= match.start && index < end) {
        return text.substring(match.start, end);
      }
    }
    return null;
  }

  static String _lineText(BufferLine line, int width) {
    final builder = StringBuffer();
    for (var x = 0; x < width; x++) {
      final codePoint = line.getCodePoint(x);
      builder.writeCharCode(codePoint == 0 ? 0x20 : codePoint);
    }
    return builder.toString();
  }

  static List<CellOffset> linkCells(Terminal terminal, int firstRow, int lastRow) {
    final cells = <CellOffset>[];
    final buffer = terminal.buffer;
    final lines = buffer.lines;
    if (lines.length == 0) return cells;

    final width = buffer.viewWidth;
    var row = firstRow.clamp(0, lines.length - 1);
    while (row > 0 && lines[row].isWrapped) {
      row--;
    }

    while (row < lines.length && row <= lastRow) {
      final builder = StringBuffer();
      final coords = <CellOffset>[];
      var last = row;
      while (true) {
        final line = lines[last];
        for (var col = 0; col < width; col++) {
          final codePoint = line.getCodePoint(col);
          builder.writeCharCode(codePoint == 0 ? 0x20 : codePoint);
          coords.add(CellOffset(col, last));
        }
        last++;
        if (last >= lines.length || !lines[last].isWrapped) break;
      }

      final text = builder.toString();
      for (final match in _pattern.allMatches(text)) {
        var stop = match.end;
        while (stop > match.start && _trailing.contains(text[stop - 1])) {
          stop--;
        }
        for (var i = match.start; i < stop; i++) {
          cells.add(coords[i]);
        }
      }
      row = last;
    }
    return cells;
  }
}
