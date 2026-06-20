import 'dart:math' as math;

/// Smooths and validates raw heading samples (compass / GPS course) so that
/// turn-by-turn guidance does not react to sensor noise.
///
/// Two safeguards are applied:
///  1. A circular exponential moving average (handles the 0/360 wrap-around).
///  2. A stability gate: a *new* heading is only considered trustworthy once
///     several consecutive raw samples agree within [stabilityToleranceDeg].
///     This is the "double-check the orientation" behaviour requested for
///     pedestrian navigation, where the magnetometer is jittery while standing
///     still.
class HeadingFilter {
  HeadingFilter({
    this.smoothingFactor = 0.35,
    this.stabilityToleranceDeg = 25.0,
    this.requiredStableSamples = 2,
    this.maxSampleAge = const Duration(seconds: 3),
  });

  /// EMA weight for the newest sample (0..1). Lower = smoother but laggier.
  final double smoothingFactor;

  /// How close consecutive raw samples must be to count as "stable".
  final double stabilityToleranceDeg;

  /// Number of agreeing raw samples required before the heading is "stable".
  final int requiredStableSamples;

  /// Samples older than this are treated as stale.
  final Duration maxSampleAge;

  double? _smoothed;
  double? _lastRaw;
  int _stableCount = 0;
  DateTime _lastUpdate = DateTime.fromMillisecondsSinceEpoch(0);

  /// The current smoothed heading, or null if no recent stable reading exists.
  double? get smoothedHeading {
    if (_smoothed == null) return null;
    if (DateTime.now().difference(_lastUpdate) > maxSampleAge) return null;
    return _smoothed;
  }

  /// Whether the filter currently has a heading it considers trustworthy.
  bool get isStable =>
      smoothedHeading != null && _stableCount >= requiredStableSamples;

  void reset() {
    _smoothed = null;
    _lastRaw = null;
    _stableCount = 0;
    _lastUpdate = DateTime.fromMillisecondsSinceEpoch(0);
  }

  /// Feed a raw heading sample (degrees, 0..360). Returns the smoothed value.
  double? addSample(double? raw) {
    if (raw == null || raw.isNaN) return smoothedHeading;

    double normalized = raw % 360;
    if (normalized < 0) normalized += 360;

    final now = DateTime.now();

    // Stability tracking on the raw signal.
    if (_lastRaw == null ||
        _angularDistance(_lastRaw!, normalized) <= stabilityToleranceDeg) {
      _stableCount = math.min(_stableCount + 1, requiredStableSamples + 5);
    } else {
      _stableCount = 1;
    }
    _lastRaw = normalized;

    // Circular EMA.
    if (_smoothed == null) {
      _smoothed = normalized;
    } else {
      _smoothed = _circularLerp(_smoothed!, normalized, smoothingFactor);
    }
    _lastUpdate = now;
    return _smoothed;
  }
}

/// Smallest absolute angular distance between two bearings (0..180).
double _angularDistance(double a, double b) {
  double diff = (a - b).abs() % 360;
  if (diff > 180) diff = 360 - diff;
  return diff;
}

/// Interpolate between two angles along the shortest arc.
double _circularLerp(double from, double to, double t) {
  final fromRad = from * math.pi / 180;
  final toRad = to * math.pi / 180;
  final x = (1 - t) * math.cos(fromRad) + t * math.cos(toRad);
  final y = (1 - t) * math.sin(fromRad) + t * math.sin(toRad);
  double deg = math.atan2(y, x) * 180 / math.pi;
  if (deg < 0) deg += 360;
  return deg;
}
