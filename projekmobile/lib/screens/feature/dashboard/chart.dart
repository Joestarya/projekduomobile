import 'dart:math';
import 'package:flutter/material.dart';

class SparklinePainter extends CustomPainter {
  final List<double> data;
  final bool isUp;

  const SparklinePainter({required this.data, required this.isUp});

  @override
  void paint(Canvas canvas, Size size) {
    if (data.length < 2) return;

    final minVal = data.reduce(min);
    final maxVal = data.reduce(max);
    final range = (maxVal - minVal).abs();
    if (range == 0) return;

    final upColor = const Color(0xFF00E676);
    final downColor = const Color(0xFFFF5252);
    final lineColor = isUp ? upColor : downColor;
    final fillColor = isUp
        ? const Color(0xFF00E676).withOpacity(0.15)
        : const Color(0xFFFF5252).withOpacity(0.15);

    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final fillPaint = Paint()
      ..color = fillColor
      ..style = PaintingStyle.fill;

    final path = Path();
    final fillPath = Path();

    for (int i = 0; i < data.length; i++) {
      final x = (i / (data.length - 1)) * size.width;
      final normalized = (data[i] - minVal) / range;
      final y =
          size.height -
          (normalized * size.height * 0.85) -
          (size.height * 0.075);

      if (i == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, size.height);
        fillPath.lineTo(x, y);
      } else {
        final prevX = ((i - 1) / (data.length - 1)) * size.width;
        final prevNorm = (data[i - 1] - minVal) / range;
        final prevY =
            size.height -
            (prevNorm * size.height * 0.85) -
            (size.height * 0.075);
        final cpX = (prevX + x) / 2;
        path.cubicTo(cpX, prevY, cpX, y, x, y);
        fillPath.cubicTo(cpX, prevY, cpX, y, x, y);
      }
    }

    fillPath.lineTo(size.width, size.height);
    fillPath.close();

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, linePaint);

    final lastX = size.width;
    final lastNorm = (data.last - minVal) / range;
    final lastY =
        size.height - (lastNorm * size.height * 0.85) - (size.height * 0.075);
    canvas.drawCircle(Offset(lastX, lastY), 2.5, Paint()..color = lineColor);
  }

  @override
  bool shouldRepaint(SparklinePainter oldDelegate) =>
      oldDelegate.data != data || oldDelegate.isUp != isUp;
}
