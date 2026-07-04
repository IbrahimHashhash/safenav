import 'dart:math' as math;
import 'package:flutter/material.dart';

class IdleView extends StatefulWidget {
  const IdleView({super.key});

  @override
  State<IdleView> createState() => _IdleViewState();
}

class _IdleViewState extends State<IdleView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  static const _colors = [
    Color(0xFF00E5FF),
    Color(0xFF2979FF),
    Color(0xFF7C4DFF),
  ];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Idle. Tap anywhere to speak',
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              height: 36,
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, _) {
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(_colors.length, (i) {
                      final p =
                          _controller.value * 2 * math.pi + i * (math.pi / 2);
                      final t = (math.sin(p) + 1) / 2;
                      final size = 14.0 + 8.0 * t;
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Opacity(
                          opacity: 0.4 + 0.6 * t,
                          child: Container(
                            width: size,
                            height: size,
                            decoration: BoxDecoration(
                              color: _colors[i],
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      );
                    }),
                  );
                },
              ),
            ),
            const SizedBox(height: 28),
            const Text(
              'Tap anywhere to speak',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
