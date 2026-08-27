import 'dart:math' as math;

import 'package:deskconn_mobile_app/theme/colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class OtpCodeField extends StatefulWidget {
  const OtpCodeField({
    super.key,
    required this.controller,
    this.focusNode,
    this.length = 6,
    this.enabled = true,
    this.onChanged,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final int length;
  final bool enabled;
  final ValueChanged<String>? onChanged;

  @override
  State<OtpCodeField> createState() => _OtpCodeFieldState();
}

class _OtpCodeFieldState extends State<OtpCodeField> {
  late List<TextEditingController> _digitControllers;
  late List<FocusNode> _focusNodes;
  late List<bool> _ownsFocusNode;
  bool _updating = false;

  @override
  void initState() {
    super.initState();
    _createFields();
    widget.controller.addListener(_syncFromParent);
    _syncFromParent();
  }

  @override
  void didUpdateWidget(covariant OtpCodeField oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_syncFromParent);
      widget.controller.addListener(_syncFromParent);
      _syncFromParent();
    }

    if (oldWidget.length != widget.length || oldWidget.focusNode != widget.focusNode) {
      _disposeFields();
      _createFields();
      _syncFromParent();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncFromParent);
    _disposeFields();
    super.dispose();
  }

  void _createFields() {
    _digitControllers = List.generate(widget.length, (_) => TextEditingController());
    _focusNodes = List.generate(
      widget.length,
      (index) => index == 0 && widget.focusNode != null ? widget.focusNode! : FocusNode(),
    );
    _ownsFocusNode = List.generate(widget.length, (index) => !(index == 0 && widget.focusNode != null));
  }

  void _disposeFields() {
    for (final controller in _digitControllers) {
      controller.dispose();
    }
    for (var i = 0; i < _focusNodes.length; i++) {
      if (_ownsFocusNode[i]) {
        _focusNodes[i].dispose();
      }
    }
  }

  String _onlyDigits(String value) => value.replaceAll(RegExp(r'\D'), '');

  void _syncFromParent() {
    if (_updating) return;

    final digits = _onlyDigits(widget.controller.text);
    final value = digits.length > widget.length ? digits.substring(0, widget.length) : digits;

    _updating = true;
    for (var i = 0; i < widget.length; i++) {
      final nextText = i < value.length ? value[i] : '';
      if (_digitControllers[i].text != nextText) {
        _digitControllers[i].value = TextEditingValue(
          text: nextText,
          selection: TextSelection.collapsed(offset: nextText.length),
        );
      }
    }
    if (widget.controller.text != value) {
      widget.controller.value = TextEditingValue(
        text: value,
        selection: TextSelection.collapsed(offset: value.length),
      );
    }
    _updating = false;
  }

  void _publish() {
    final value = _digitControllers.map((controller) => controller.text).join();

    _updating = true;
    widget.controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
    _updating = false;

    widget.onChanged?.call(value);
  }

  void _focusField(int index) {
    _focusNodes[index].requestFocus();
    _digitControllers[index].selection = TextSelection.collapsed(offset: _digitControllers[index].text.length);
  }

  void _handleInput(int index, String rawValue) {
    if (_updating) return;

    final digits = _onlyDigits(rawValue);
    final previousValue = widget.controller.text;

    if (digits.isEmpty) {
      _digitControllers[index].clear();
      _publish();
      return;
    }

    if (digits.length == 1) {
      _digitControllers[index].value = TextEditingValue(
        text: digits,
        selection: const TextSelection.collapsed(offset: 1),
      );
      _publish();

      if (index < widget.length - 1) {
        _focusField(index + 1);
      } else {
        _focusNodes[index].unfocus();
      }
      return;
    }

    if (digits.length == 2 && index < previousValue.length && digits[0] == previousValue[index]) {
      _digitControllers[index].value = TextEditingValue(
        text: digits[1],
        selection: const TextSelection.collapsed(offset: 1),
      );
      _publish();

      if (index < widget.length - 1) {
        _focusField(index + 1);
      } else {
        _focusNodes[index].unfocus();
      }
      return;
    }

    var targetIndex = index;
    for (final digit in digits.characters) {
      if (targetIndex >= widget.length) break;
      _digitControllers[targetIndex].value = TextEditingValue(
        text: digit,
        selection: const TextSelection.collapsed(offset: 1),
      );
      targetIndex++;
    }

    _publish();

    final nextIndex = math.min(targetIndex, widget.length - 1);
    if (targetIndex < widget.length) {
      _focusField(nextIndex);
    } else {
      _focusNodes[nextIndex].unfocus();
    }
  }

  void _handleBackspace(int index) {
    if (_digitControllers[index].text.isNotEmpty) {
      _digitControllers[index].clear();
      _publish();
      _focusField(index);
      return;
    }

    if (index == 0) return;

    final previousIndex = index - 1;
    _digitControllers[previousIndex].clear();
    _publish();
    _focusField(previousIndex);
  }

  String? _extractOtpCode(String? value) {
    if (value == null) return null;

    final match = RegExp(r'\d+').allMatches(value).map((match) => match.group(0)!).firstWhere(
          (digits) => digits.length == widget.length,
          orElse: () => '',
        );

    return match.isEmpty ? null : match;
  }

  void _fillCode(String code) {
    _updating = true;
    for (var i = 0; i < widget.length; i++) {
      _digitControllers[i].value = TextEditingValue(
        text: code[i],
        selection: const TextSelection.collapsed(offset: 1),
      );
    }
    _updating = false;

    _publish();
    _focusNodes.last.unfocus();
  }

  Future<void> _handlePasteMenu(LongPressStartDetails details) async {
    if (!widget.enabled) return;

    final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
    final code = _extractOtpCode(clipboard?.text);
    if (code == null || !mounted) return;

    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        details.globalPosition & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: const [
        PopupMenuItem(
          value: 'paste',
          child: Text('Paste code'),
        ),
      ],
    );

    if (selected == 'paste' && mounted) {
      _fillCode(code);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final palette = DeskconnPalette.of(context);
    final textStyle = theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600, color: palette.heading);

    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 6.0;
        final availableWidth = constraints.maxWidth.isFinite ? constraints.maxWidth : 320.0;
        final boxSize = math.min(56.0, (availableWidth - gap * (widget.length - 1)) / widget.length);

        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(widget.length, (index) {
            return Padding(
              padding: EdgeInsets.only(right: index == widget.length - 1 ? 0 : gap),
              child: SizedBox.square(
                dimension: boxSize,
                child: _OtpDigitField(
                  controller: _digitControllers[index],
                  focusNode: _focusNodes[index],
                  enabled: widget.enabled,
                  textStyle: textStyle,
                  colorScheme: colorScheme,
                  palette: palette,
                  textInputAction: index == widget.length - 1 ? TextInputAction.done : TextInputAction.next,
                  onTap: () => _focusField(index),
                  onLongPressStart: _handlePasteMenu,
                  onChanged: (value) => _handleInput(index, value),
                  onBackspace: () => _handleBackspace(index),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

class _OtpDigitField extends StatefulWidget {
  const _OtpDigitField({
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.textStyle,
    required this.colorScheme,
    required this.palette,
    required this.textInputAction,
    required this.onTap,
    required this.onLongPressStart,
    required this.onChanged,
    required this.onBackspace,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final TextStyle? textStyle;
  final ColorScheme colorScheme;
  final DeskconnPalette palette;
  final TextInputAction textInputAction;
  final VoidCallback onTap;
  final GestureLongPressStartCallback onLongPressStart;
  final ValueChanged<String> onChanged;
  final VoidCallback onBackspace;

  @override
  State<_OtpDigitField> createState() => _OtpDigitFieldState();
}

class _OtpDigitFieldState extends State<_OtpDigitField> {
  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_handleStateChanged);
    widget.controller.addListener(_handleStateChanged);
  }

  @override
  void didUpdateWidget(covariant _OtpDigitField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.removeListener(_handleStateChanged);
      widget.focusNode.addListener(_handleStateChanged);
    }
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleStateChanged);
      widget.controller.addListener(_handleStateChanged);
    }
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_handleStateChanged);
    widget.controller.removeListener(_handleStateChanged);
    super.dispose();
  }

  void _handleStateChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(12);
    final colors = _OtpDigitColors.resolve(colorScheme: widget.colorScheme, palette: widget.palette);
    final isFocused = widget.focusNode.hasFocus;
    final borderColor = isFocused
        ? colors.focusedBorder
        : widget.enabled
        ? colors.border
        : colors.disabledBorder;
    final borderWidth = isFocused ? 1.8 : 1.15;

    return Focus(
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.backspace) {
          widget.onBackspace();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.enabled ? widget.onTap : null,
        onLongPressStart: widget.enabled ? widget.onLongPressStart : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: widget.enabled ? colors.fill : colors.disabledFill,
            borderRadius: borderRadius,
            border: Border.all(color: borderColor, width: borderWidth),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Text(widget.controller.text, textAlign: TextAlign.center, style: widget.textStyle),
              if (isFocused && widget.enabled)
                _OtpVisualCursor(digit: widget.controller.text, color: colors.cursor, textStyle: widget.textStyle),
              Positioned.fill(
                child: IgnorePointer(
                  child: Opacity(
                    opacity: 0,
                    child: EditableText(
                      controller: widget.controller,
                      focusNode: widget.focusNode,
                      readOnly: !widget.enabled,
                      showCursor: false,
                      cursorColor: colors.cursor,
                      backgroundCursorColor: colors.disabledBorder,
                      keyboardType: TextInputType.number,
                      textInputAction: widget.textInputAction,
                      textAlign: TextAlign.center,
                      style: widget.textStyle ?? const TextStyle(),
                      maxLines: 1,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      onChanged: widget.onChanged,
                      onSubmitted: (_) => FocusScope.of(context).unfocus(),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OtpVisualCursor extends StatelessWidget {
  const _OtpVisualCursor({required this.digit, required this.color, required this.textStyle});

  final String digit;
  final Color color;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final digitPainter = TextPainter(
          text: TextSpan(text: digit, style: textStyle),
          textDirection: TextDirection.ltr,
        )..layout();

        final cursorLeft = digit.isEmpty
            ? (constraints.maxWidth - 2) / 2
            : (constraints.maxWidth + digitPainter.width) / 2 + 2;

        return Stack(
          children: [
            Positioned(
              left: cursorLeft.clamp(0, constraints.maxWidth - 2),
              top: (constraints.maxHeight - 24) / 2,
              child: Container(
                width: 2,
                height: 24,
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(1)),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _OtpDigitColors {
  const _OtpDigitColors({
    required this.fill,
    required this.disabledFill,
    required this.border,
    required this.focusedBorder,
    required this.disabledBorder,
    required this.cursor,
  });

  final Color fill;
  final Color disabledFill;
  final Color border;
  final Color focusedBorder;
  final Color disabledBorder;
  final Color cursor;

  static _OtpDigitColors resolve({required ColorScheme colorScheme, required DeskconnPalette palette}) {
    final isDark = colorScheme.brightness == Brightness.dark;

    final fill = isDark ? Color.lerp(palette.surface, palette.surfaceTint, 0.45)! : palette.surface;
    final border = isDark
        ? Color.lerp(palette.border, palette.text, 0.32)!
        : Color.lerp(palette.border, palette.text, 0.30)!;
    final disabledFill = isDark ? Color.lerp(palette.surface, palette.background, 0.35)! : palette.surfaceTint;
    final disabledBorder = isDark ? Color.lerp(palette.border, palette.background, 0.25)! : palette.border;

    return _OtpDigitColors(
      fill: fill,
      disabledFill: disabledFill,
      border: border,
      focusedBorder: colorScheme.primary,
      disabledBorder: disabledBorder,
      cursor: colorScheme.primary,
    );
  }
}
