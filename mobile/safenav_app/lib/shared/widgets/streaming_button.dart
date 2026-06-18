import 'package:flutter/material.dart';

/// Start/stop button for streaming camera frames to the detection server.
/// Shared by the user and developer screens so both control the same stream.
class StreamingButton extends StatelessWidget {
  const StreamingButton({
    super.key,
    required this.streaming,
    required this.busy,
    required this.onPressed,
  });

  final bool streaming;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final label =
        streaming ? 'Stop obstacle detection' : 'Start obstacle detection';

    return Semantics(
      button: true,
      label: label,
      child: ElevatedButton.icon(
        onPressed: busy ? null : onPressed,
        icon: busy
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Icon(streaming ? Icons.stop : Icons.videocam),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          minimumSize: const Size.fromHeight(54),
          backgroundColor:
              streaming ? Colors.red.shade700 : Colors.green.shade700,
          foregroundColor: Colors.white,
          textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
