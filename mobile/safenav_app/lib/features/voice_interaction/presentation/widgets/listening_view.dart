import 'package:flutter/material.dart';
import 'sound_wave.dart';

class ListeningView extends StatelessWidget {
  const ListeningView({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Listening',
      liveRegion: true,
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SoundWave(
              colors: [Colors.white, Colors.white],
              duration: Duration(milliseconds: 2400),
            ),
            SizedBox(height: 28),
            Text(
              'Listening...',
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
