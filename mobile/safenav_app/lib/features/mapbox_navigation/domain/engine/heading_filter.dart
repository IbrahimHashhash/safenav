// Smooths a noisy compass heading and decides when it is trustworthy.
//
//   1. Circular moving average over a sliding window (handles 0/360 wrap).
//   2. Stability gate: several CONSECUTIVE samples must agree (within a
//      tolerance of the running mean) before the heading is trusted; a wild
//      jump resets stability and the window ("double-check" the heading).
//
// Pure Dart, no Flutter/SDK dependencies. Ported from the Google-nav engine.

import 'geo_math.dart';

class HeadingEstimate {
  /// Smoothed heading in degrees [0,360), or null when no data yet.
  final double? smoothedHeading;

  /// True only when enough recent samples have agreed.
  final bool isStable;

  const HeadingEstimate({required this.smoothedHeading, required this.isStable});

  static const HeadingEstimate empty =
      HeadingEstimate(smoothedHeading: null, isStable: false);
}

class HeadingFilter {
  final int windowSize;
  final double stabilityToleranceDeg;
  final int requiredStableSamples;
  final double jumpResetThresholdDeg;

  final List<double> _window = <double>[];
  int _consecutiveStable = 0;
  double? _lastMean;

  HeadingFilter({
    this.windowSize = 6,
    this.stabilityToleranceDeg = 12.0,
    this.requiredStableSamples = 4,
    this.jumpResetThresholdDeg = 45.0,
  })  : assert(windowSize >= 1),
        assert(requiredStableSamples >= 1);

  HeadingEstimate get current => HeadingEstimate(
        smoothedHeading: _lastMean,
        isStable: _consecutiveStable >= requiredStableSamples,
      );

  void reset() {
    _window.clear();
    _consecutiveStable = 0;
    _lastMean = null;
  }

  HeadingEstimate add(double rawHeadingDeg) {
    final heading = GeoMath.normalizeDegrees(rawHeadingDeg);

    if (_lastMean != null &&
        GeoMath.angularDistance(_lastMean!, heading) > jumpResetThresholdDeg) {
      _window.clear();
      _window.add(heading);
      _lastMean = heading;
      _consecutiveStable = 1;
      return current;
    }

    _window.add(heading);
    if (_window.length > windowSize) {
      _window.removeAt(0);
    }

    final mean = GeoMath.circularMeanDegrees(_window)!;

    if (GeoMath.angularDistance(mean, heading) <= stabilityToleranceDeg) {
      _consecutiveStable++;
    } else {
      _consecutiveStable = 1;
    }

    _lastMean = mean;
    return current;
  }
}
