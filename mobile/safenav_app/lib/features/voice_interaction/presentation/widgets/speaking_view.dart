import 'package:flutter/material.dart';

class SpeakingView extends StatelessWidget {
  const SpeakingView({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.volume_up_rounded,
            size: 100,
          ),
          SizedBox(height: 20),
          Text(
            'Speaking...',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}