import 'package:flutter/widgets.dart';
import 'package:xterm/core.dart';

class TerminalSelectionMath {
  TerminalSelectionMath._();

  static Offset handleDragPoint({required bool isStart, required Offset position, required Size cellSize}) {
    if (isStart) return position;
    return position - Offset(cellSize.width / 2, cellSize.height / 2);
  }

  static ({CellOffset begin, CellOffset end}) rangeForEdge({required CellOffset moving, required CellOffset anchor}) {
    final before = moving.isBefore(anchor);
    return (begin: before ? moving : anchor, end: before ? anchor : moving);
  }
}
