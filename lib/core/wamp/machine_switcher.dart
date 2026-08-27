import 'package:deskconn_mobile_app/providers/session_provider.dart';
import 'package:deskconn_mobile_app/screens/settings_screen.dart';
import 'package:deskconn_mobile_app/widgets/machine_grid.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

Future<void> switchMachine(BuildContext context, {String? currentRealm}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _MachineSwitcherSheet(currentRealm: currentRealm),
  );
}

class _MachineSwitcherSheet extends StatelessWidget {
  final String? currentRealm;

  const _MachineSwitcherSheet({this.currentRealm});

  static const _crossAxisCount = 2;
  static const _rowHeight = 56.0;
  static const _rowSpacing = 10.0;
  static const _headerHeight = 80.0;
  static const _gridVerticalPadding = 32.0;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final desktopCount = context.watch<SessionProvider>().desktops.length;

    final rows = (desktopCount / _crossAxisCount).ceil();
    // Size the sheet to the actual rows plus one extra row of breathing
    // room / scroll hint, instead of always taking a fixed screen fraction.
    final visibleRows = (rows + 1).clamp(1, 1 << 30);
    final contentHeight =
        _headerHeight + _gridVerticalPadding + visibleRows * _rowHeight + (visibleRows - 1) * _rowSpacing;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.9;
    final sheetHeight = contentHeight.clamp(220.0, maxHeight);

    return SizedBox(
      height: sheetHeight,
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: colorScheme.outlineVariant, borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 8, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Switch Machine',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.settings_outlined, color: colorScheme.onSurface),
                    tooltip: 'Settings',
                    onPressed: () =>
                        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
                  ),
                ],
              ),
            ),
            Expanded(child: MachineGrid(currentRealm: currentRealm)),
          ],
        ),
      ),
    );
  }
}
