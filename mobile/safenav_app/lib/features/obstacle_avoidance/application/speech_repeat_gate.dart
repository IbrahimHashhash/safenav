/// Suppresses repeats of the *same* guidance within a cooldown window.
///
/// The important part is how the de-duplication KEY is built (see [keyFor]):
///   * For a line about a detected obstacle, the key is the obstacle TYPE +
///     region only — the distance is deliberately excluded. So "chair 3 meters
///     ahead" and "chair 2 meters ahead" map to the same key and the repeat is
///     suppressed, while a different obstacle ("car ahead") or a different
///     region is NOT suppressed.
///   * For a general line with no obstacle (e.g. "path is clear"), the
///     normalized text is used so those still de-duplicate.
///
/// The gate itself is a pure exact-key recency map, robust to flickering
/// detections (a repeat is dropped even if other lines played in between) and
/// time-injectable for testing.
class SpeechRepeatGate {
  SpeechRepeatGate(this.cooldown);

  final Duration cooldown;
  final Map<String, DateTime> _lastSpokenAt = {};

  /// Returns true if a line with [key] may be spoken at [now]; records the time
  /// when it returns true so repeats of the same key within [cooldown] drop.
  bool allow(String key, DateTime now) {
    if (key.isEmpty) return false;

    // Age out old entries so the map can't grow without bound.
    _lastSpokenAt.removeWhere((_, t) => now.difference(t) >= cooldown);

    final last = _lastSpokenAt[key];
    if (last != null && now.difference(last) < cooldown) {
      return false;
    }
    _lastSpokenAt[key] = now;
    return true;
  }

  /// Clears history (e.g. when detection restarts) so the next line plays.
  void reset() => _lastSpokenAt.clear();

  /// Builds the de-duplication key for a guidance line.
  ///
  /// When [label] names a detected obstacle, the key is the obstacle type plus
  /// [region] (NOT the distance), so the same obstacle at a changing distance
  /// collapses to one key. Otherwise the [text] is normalized (lowercased,
  /// digits/punctuation stripped) and used as the key.
  static String keyFor({String? label, int? region, required String text}) {
    final normalizedLabel = (label ?? '').trim().toLowerCase();
    if (normalizedLabel.isNotEmpty) {
      return 'obstacle|$normalizedLabel|${region ?? -1}';
    }
    return 'text|${normalize(text)}';
  }

  /// Lowercased, digits and punctuation removed, whitespace collapsed.
  static String normalize(String text) => text
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z ]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
