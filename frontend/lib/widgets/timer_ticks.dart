import 'dart:math' as math;

import 'package:flutter/material.dart';

class TimerTicks extends StatelessWidget {
  final double size;
  final int tickCount;
  final double tickLength;
  final double tickWidth;
  final Color color;

  const TimerTicks({
    super.key,
    this.size = 300,
    this.tickCount = 60,
    this.tickLength = 8,
    this.tickWidth = 2,
    this.color = Colors.white38,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _TimerTicksPainter(
          tickCount: tickCount,
          tickLength: tickLength,
          tickWidth: tickWidth,
          color: color,
        ),
      ),
    );
  }
}

class _TimerTicksPainter extends CustomPainter {
  final int tickCount;
  final double tickLength;
  final double tickWidth;
  final Color color;

  _TimerTicksPainter({
    required this.tickCount,
    required this.tickLength,
    required this.tickWidth,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    final radius = size.width / 2 - 2;

    final paint = Paint()
      ..color = color
      ..strokeWidth = tickWidth
      ..strokeCap = StrokeCap.round;

    for (int i = 0; i < tickCount; i++) {
      final angle = (i / tickCount) * 2 * math.pi - math.pi / 2;

      final isMajor = i % 5 == 0;

      final length = isMajor ? tickLength * 1.6 : tickLength;

      final width = isMajor ? tickWidth * 1.4 : tickWidth;

      paint.strokeWidth = width;

      final outerPoint = Offset(
        center.dx + math.cos(angle) * radius,
        center.dy + math.sin(angle) * radius,
      );

      final innerPoint = Offset(
        center.dx + math.cos(angle) * (radius - length),
        center.dy + math.sin(angle) * (radius - length),
      );

      canvas.drawLine(innerPoint, outerPoint, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _TimerTicksPainter oldDelegate) {
    return false;
  }
}
