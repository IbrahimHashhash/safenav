import 'package:flutter/material.dart';

class SpeakingView extends StatelessWidget {

  final String text;

  const SpeakingView({
    super.key,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {

    return Center(
      child: Padding(
        padding:
            const EdgeInsets.all(24.0),

        child: Column(
          mainAxisAlignment:
              MainAxisAlignment.center,

          children: [

            const Icon(
              Icons.volume_up_rounded,
              size: 100,
            ),

            const SizedBox(height: 20),

            Text(
              text,
              textAlign: TextAlign.center,

              style: const TextStyle(
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