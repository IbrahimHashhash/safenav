import 'package:flutter/material.dart';
import 'sound_wave.dart';

class SpeakingView extends StatelessWidget {
  const SpeakingView({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Speaking',
      liveRegion: true,
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SoundWave(
              colors: [
                Color(0xFFFF4D9D),
                Color(0xFF9C4DFF),
                Color(0xFF4D7CFF),
              ],
              duration: Duration(milliseconds: 1600),
            ),
            SizedBox(height: 28),
            Text(
              'Speaking...',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
