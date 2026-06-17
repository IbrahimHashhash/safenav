import 'dart:math' as math;
import 'package:flutter/material.dart';

class SoundWave extends StatefulWidget {
  final List<Color> colors;
  final double width;
  final double height;
  final int barCount;
  final Duration duration;

  const SoundWave({
    super.key,
    required this.colors,
    this.width = 220,
    this.height = 120,
    this.barCount = 7,
    this.duration = const Duration(milliseconds: 1400),
  });

  @override
  State<SoundWave> createState() => _SoundWaveState();
}

class _SoundWaveState extends State<SoundWave>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration)
      ..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return CustomPaint(
            painter: _WavePainter(
              phase: _controller.value,
              colors: widget.colors,
              barCount: widget.barCount,
            ),
          );
        },
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  final double phase;
  final List<Color> colors;
  final int barCount;

  _WavePainter({
    required this.phase,
    required this.colors,
    required this.barCount,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final slot = size.width / (barCount * 2 - 1);
    final barWidth = slot;
    final centerY = size.height / 2;

    final shader = LinearGradient(
      colors: colors,
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
    ).createShader(Offset.zero & size);

    final barPaint = Paint()
      ..shader = shader
      ..style = PaintingStyle.fill;

    final glowPaint = Paint()
      ..shader = shader
      ..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);

    for (int i = 0; i < barCount; i++) {
      final p = phase * 2 * math.pi + i * (math.pi / barCount) * 1.6;
      final norm = (math.sin(p) + 1) / 2;
      final barHeight = size.height * (0.18 + 0.82 * norm);
      final x = i * slot * 2;
      final top = centerY - barHeight / 2;

      final rrect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, top, barWidth, barHeight),
        Radius.circular(barWidth / 2),
      );

      canvas.drawRRect(rrect, glowPaint);
      canvas.drawRRect(rrect, barPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _WavePainter oldDelegate) =>
      oldDelegate.phase != phase ||
      oldDelegate.colors != colors ||
      oldDelegate.barCount != barCount;
}
