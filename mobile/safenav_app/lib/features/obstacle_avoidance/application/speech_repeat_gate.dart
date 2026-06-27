/// Suppresses repeats of the *same* guidance within a cooldown window.
///
/// The important part is how the de-duplication KEY is built (see [keyFor]):
///   * For a line about a detected obstacle, the key is the obstacle TYPE +
///     region only — the distance is deliberately excluded. So "chair 3 meters
///     ahead" and "chair 2 meters ahead" map to the same key, while a different
///     obstacle ("car ahead") or a different region is a different key.
///   * For a general line with no obstacle (e.g. "path is clear"), the
///     normalized text is used so those still de-duplicate.
///
/// De-duplication is also DISTANCE-AWARE: callers may pass the obstacle's
/// distance and a [allow]-time threshold. A repeat of the same key within the
/// cooldown is normally suppressed, but if the distance changed by MORE than
/// the threshold (e.g. a car closing from 10 m to 5 m) it is allowed through so
/// the updated distance is announced. Changes of the threshold or less stay
/// suppressed. Passing no distance / a zero threshold keeps pure time-based
/// behaviour.
///
/// The gate itself is a pure exact-key recency map, robust to flickering
/// detections (a repeat is dropped even if other lines played in between) and
/// time-injectable for testing.
class SpeechRepeatGate {
  SpeechRepeatGate(this.cooldown);

  final Duration cooldown;
  final Map<String, _GateEntry> _lastSpokenAt = {};

  /// Returns true if a line with [key] may be spoken at [now]; records the time
  /// (and [distance]) when it returns true so repeats of the same key within
  /// [cooldown] drop.
  ///
  /// When [distanceThreshold] is greater than zero and both the current
  /// [distance] and the last recorded distance are known, a repeat within the
  /// cooldown is allowed if the distance changed by MORE than
  /// [distanceThreshold] meters. A change of exactly the threshold (or less) is
  /// treated as the same event and stays suppressed.
  bool allow(
    String key,
    DateTime now, {
    double? distance,
    double distanceThreshold = 0.0,
  }) {
    if (key.isEmpty) return false;

    // Age out old entries so the map can't grow without bound. After this, any
    // remaining entry for [key] is necessarily within the cooldown window.
    _lastSpokenAt.removeWhere((_, e) => now.difference(e.at) >= cooldown);

    final last = _lastSpokenAt[key];
    if (last != null) {
      final movedEnough = distanceThreshold > 0 &&
          distance != null &&
          last.distance != null &&
          (distance - last.distance!).abs() > distanceThreshold;
      if (!movedEnough) return false;
    }

    _lastSpokenAt[key] = _GateEntry(now, distance);
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

/// One recorded "last spoken" event: when it was spoken and the distance (if
/// any) reported at that time, used for distance-aware de-duplication.
class _GateEntry {
  const _GateEntry(this.at, this.distance);
  final DateTime at;
  final double? distance;
}
