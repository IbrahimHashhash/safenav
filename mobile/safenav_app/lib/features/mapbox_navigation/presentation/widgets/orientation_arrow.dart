import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A Google-Maps-style location puck with a heading cone/arrow.
///
/// [headingDegrees] is the smoothed compass heading (0 = north, clockwise).
/// When null, only the dot is shown (orientation not yet known).
class OrientationArrow extends StatelessWidget {
  const OrientationArrow({
    super.key,
    required this.headingDegrees,
    this.color = const Color(0xFF1A73E8),
    this.size = 46,
  });

  final double? headingDegrees;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final rotation =
        headingDegrees == null ? 0.0 : headingDegrees! * math.pi / 180.0;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (headingDegrees != null)
            Transform.rotate(
              angle: rotation,
              child: CustomPaint(
                size: Size(size, size),
                painter: _HeadingConePainter(color: color),
              ),
            ),
          // Accuracy halo.
          Container(
            width: size * 0.42,
            height: size * 0.42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.18),
            ),
          ),
          // Solid puck.
          Container(
            width: size * 0.3,
            height: size * 0.3,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              border: Border.all(color: Colors.white, width: 2.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 3,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeadingConePainter extends CustomPainter {
  _HeadingConePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // Cone pointing "up" (north before rotation is applied by the caller).
    final coneWidth = 0.5; // radians, half-angle ~14°
    final rect = Rect.fromCircle(center: center, radius: radius);
    final start = -math.pi / 2 - coneWidth;
    final sweep = coneWidth * 2;

    final gradient = RadialGradient(
      colors: [color.withValues(alpha: 0.55), color.withValues(alpha: 0.0)],
    );
    final paint = Paint()
      ..shader = gradient.createShader(rect)
      ..style = PaintingStyle.fill;

    final path = Path()
      ..moveTo(center.dx, center.dy)
      ..arcTo(rect, start, sweep, false)
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _HeadingConePainter oldDelegate) =>
      oldDelegate.color != color;
}
