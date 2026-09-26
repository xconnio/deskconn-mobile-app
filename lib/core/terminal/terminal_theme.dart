import 'package:flutter/widgets.dart';
import 'package:xterm/ui.dart';

const int kTerminalAccentR = 0x42;
const int kTerminalAccentG = 0x85;
const int kTerminalAccentB = 0xF4;

const kTerminalAccent = Color.fromARGB(0xFF, kTerminalAccentR, kTerminalAccentG, kTerminalAccentB);
const kTerminalSelection = Color.fromARGB(0x66, kTerminalAccentR, kTerminalAccentG, kTerminalAccentB);

final kTerminalTheme = _buildTerminalTheme();

TerminalTheme _buildTerminalTheme() {
  const base = TerminalThemes.defaultTheme;
  return TerminalTheme(
    cursor: base.cursor,
    selection: kTerminalSelection,
    foreground: base.foreground,
    background: base.background,
    black: base.black,
    red: base.red,
    green: base.green,
    yellow: base.yellow,
    blue: base.blue,
    magenta: base.magenta,
    cyan: base.cyan,
    white: base.white,
    brightBlack: base.brightBlack,
    brightRed: base.brightRed,
    brightGreen: base.brightGreen,
    brightYellow: base.brightYellow,
    brightBlue: base.brightBlue,
    brightMagenta: base.brightMagenta,
    brightCyan: base.brightCyan,
    brightWhite: base.brightWhite,
    searchHitBackground: base.searchHitBackground,
    searchHitBackgroundCurrent: base.searchHitBackgroundCurrent,
    searchHitForeground: base.searchHitForeground,
  );
}
