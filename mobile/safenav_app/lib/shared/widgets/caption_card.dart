import 'package:flutter/material.dart';

/// A labelled caption box. When the text is longer than [maxHeight] it becomes
/// scrollable with a visible scrollbar instead of growing without bound.
class CaptionCard extends StatefulWidget {
  const CaptionCard({
    super.key,
    required this.label,
    required this.text,
    required this.icon,
    required this.accent,
    this.maxHeight = 120,
  });

  final String label;
  final String text;
  final IconData icon;
  final Color accent;
  final double maxHeight;

  @override
  State<CaptionCard> createState() => _CaptionCardState();
}

class _CaptionCardState extends State<CaptionCard> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasText = widget.text.trim().isNotEmpty;

    return Semantics(
      liveRegion: true,
      label: hasText ? '${widget.label}: ${widget.text}' : null,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: widget.accent.withValues(alpha: 0.6)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(widget.icon, color: widget.accent, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.label,
                    style: TextStyle(
                      color: widget.accent,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: widget.maxHeight),
                    child: Scrollbar(
                      controller: _scrollController,
                      thumbVisibility: true,
                      child: SingleChildScrollView(
                        controller: _scrollController,
                        child: Text(
                          hasText ? widget.text : '—',
                          style: TextStyle(
                            color: hasText ? Colors.white : Colors.white38,
                            fontSize: 16,
                            height: 1.3,
                          ),
                        ),
                      ),
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
