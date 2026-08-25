import 'package:flutter/material.dart';

class SparklineChart extends StatelessWidget {
  final List<double> values;
  final double? maxValue;
  final Color color;
  final double strokeWidth;

  const SparklineChart({super.key, required this.values, this.maxValue, required this.color, this.strokeWidth = 2});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _SparklinePainter(values: values, maxValue: maxValue, color: color, strokeWidth: strokeWidth),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  final List<double> values;
  final double? maxValue;
  final Color color;
  final double strokeWidth;

  _SparklinePainter({required this.values, required this.maxValue, required this.color, required this.strokeWidth});

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;

    final ceiling = maxValue ?? values.fold<double>(1, (m, v) => v > m ? v : m);
    final effectiveCeiling = ceiling <= 0 ? 1 : ceiling;

    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = (i / (values.length - 1)) * size.width;
      final clamped = values[i].clamp(0, effectiveCeiling).toDouble();
      final y = size.height - (clamped / effectiveCeiling) * size.height;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) {
    return oldDelegate.values != values || oldDelegate.maxValue != maxValue || oldDelegate.color != color;
  }
}
