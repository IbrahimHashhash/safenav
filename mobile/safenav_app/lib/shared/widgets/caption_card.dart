import 'package:flutter/material.dart';





class CaptionCard extends StatelessWidget {
  const CaptionCard({
    super.key,
    required this.label,
    required this.text,
    required this.icon,
    required this.accent,
    this.maxLines = 4,
  });

  final String label;
  final String text;
  final IconData icon;
  final Color accent;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final hasText = text.trim().isNotEmpty;

    return Semantics(
      liveRegion: true,
      label: hasText ? '$label: $text' : null,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          
          
          color: const Color(0xFF121212).withValues(alpha: 0.30),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: accent.withValues(alpha: 0.7), size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: accent.withValues(alpha: 0.7),
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    hasText ? text : '—',
                    maxLines: maxLines,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: hasText ? Colors.white : Colors.white38,
                      fontSize: 16,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
