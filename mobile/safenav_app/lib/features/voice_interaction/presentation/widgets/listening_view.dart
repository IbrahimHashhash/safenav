import 'package:flutter/material.dart';

class ListeningView extends StatelessWidget {
  const ListeningView({super.key});

  @override
  Widget build(BuildContext context) {

    return const Center(
      child: Column(
        mainAxisAlignment:
            MainAxisAlignment.center,

        children: [

          Icon(
            Icons.mic,
            size: 120,
          ),

          SizedBox(height: 20),

          Text(
            'Listening...',
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