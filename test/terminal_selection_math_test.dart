import 'package:deskconn_mobile_app/core/terminal/terminal_links.dart';
import 'package:deskconn_mobile_app/core/terminal/terminal_selection_math.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/core.dart';

void main() {
  underlineChecks();
  const cellSize = Size(10, 20);

  group('handleDragPoint', () {
    test('start handle resolves at the touched cell', () {
      expect(
        TerminalSelectionMath.handleDragPoint(isStart: true, position: const Offset(100, 40), cellSize: cellSize),
        const Offset(100, 40),
      );
    });

    test('end handle steps back half a cell so it does not fall on the next row', () {
      expect(
        TerminalSelectionMath.handleDragPoint(isStart: false, position: const Offset(100, 40), cellSize: cellSize),
        const Offset(95, 30),
      );
    });
  });

  group('rangeForEdge', () {
    test('dragging the start handle forward shrinks the selection', () {
      final range = TerminalSelectionMath.rangeForEdge(
        moving: const CellOffset(12, 0),
        anchor: const CellOffset(20, 0),
      );
      expect(range.begin, const CellOffset(12, 0));
      expect(range.end, const CellOffset(20, 0));
    });

    test('dragging the start handle backwards grows the selection', () {
      final range = TerminalSelectionMath.rangeForEdge(moving: const CellOffset(2, 0), anchor: const CellOffset(20, 0));
      expect(range.begin, const CellOffset(2, 0));
      expect(range.end, const CellOffset(20, 0));
    });

    test('dragging the start handle past the end swaps the edges', () {
      final range = TerminalSelectionMath.rangeForEdge(
        moving: const CellOffset(30, 0),
        anchor: const CellOffset(20, 0),
      );
      expect(range.begin, const CellOffset(20, 0));
      expect(range.end, const CellOffset(30, 0));
    });

    test('dragging the end handle past the start swaps the edges', () {
      final range = TerminalSelectionMath.rangeForEdge(moving: const CellOffset(4, 0), anchor: const CellOffset(20, 0));
      expect(range.begin, const CellOffset(4, 0));
      expect(range.end, const CellOffset(20, 0));
    });

    test('handles can go back and forth across several rows', () {
      const anchor = CellOffset(30, 1);
      for (final moving in [
        const CellOffset(10, 0),
        const CellOffset(45, 2),
        const CellOffset(5, 0),
        const CellOffset(60, 3),
        const CellOffset(30, 1),
      ]) {
        final range = TerminalSelectionMath.rangeForEdge(moving: moving, anchor: anchor);
        expect(
          range.begin.isBefore(range.end) || range.begin.isEqual(range.end),
          isTrue,
          reason: 'range must always be ordered, dragging to $moving',
        );
        expect({range.begin, range.end}, {moving, anchor});
      }
    });
  });
}

void underlineChecks() {
  group('link underline', () {
    test('sits on the bottom of the row and spans the whole link', () {
      final rect = TerminalLinks.underlineRect(
        originX: 10,
        rowTop: 100,
        cellWidth: 8,
        cellHeight: 16,
        firstColumn: 2,
        lastColumn: 5,
      );
      expect(rect.left, 10 + 2 * 8);
      expect(rect.width, 4 * 8);
      expect(rect.bottom, 116);
      expect(rect.height, greaterThan(0));
    });
  });
}
