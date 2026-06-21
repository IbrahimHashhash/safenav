import 'dart:async';
import 'dart:math' as math;

import 'package:geolocator/geolocator.dart';

/// A single walking-speed reading.
class WalkingSpeedSample {
  /// Instantaneous speed (m/s); 0 while stopped.
  final double currentMps;

  /// Average speed over the time the user was actually walking (m/s).
  final double averageMps;

  /// Whether the user is currently moving.
  final bool moving;

  const WalkingSpeedSample({
    required this.currentMps,
    required this.averageMps,
    required this.moving,
  });

  static const WalkingSpeedSample zero =
      WalkingSpeedSample(currentMps: 0, averageMps: 0, moving: false);

  double get currentKmh => currentMps * 3.6;
  double get averageKmh => averageMps * 3.6;
}

/// Tracks the user's walking speed from GPS fixes and keeps a running AVERAGE
/// over moving time (stationary periods are excluded). When the user stops, the
/// last accumulated average remains available.
///
/// The speed math ([addSample]) is pure and unit-testable; [start] just wires
/// it to the Geolocator position stream.
class WalkingSpeedTracker {
  /// Below this speed (m/s) the user is considered stopped.
  static const double _movingThresholdMps = 0.3;

  /// Reject implausibly large jumps (GPS spikes) from the average.
  static const double _maxPlausibleMps = 8.0;

  final StreamController<WalkingSpeedSample> _controller =
      StreamController<WalkingSpeedSample>.broadcast();

  Stream<WalkingSpeedSample> get samples => _controller.stream;
  WalkingSpeedSample get current => _last;
  bool get isTracking => _sub != null;

  WalkingSpeedSample _last = WalkingSpeedSample.zero;

  StreamSubscription<Position>? _sub;
  double? _prevLat;
  double? _prevLng;
  DateTime? _prevTime;
  double _movingDistance = 0; // metres accumulated while moving
  double _movingSeconds = 0; // seconds accumulated while moving

  Future<bool> start() async {
    if (_sub != null) return true;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return false;
    }

    // Don't bridge the gap across a pause.
    _prevLat = null;
    _prevLng = null;
    _prevTime = null;

    _sub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 1,
      ),
    ).listen((pos) {
      addSample(
        lat: pos.latitude,
        lng: pos.longitude,
        time: pos.timestamp,
        gpsSpeedMps: pos.speed,
      );
    });
    return true;
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
  }

  /// Clears the recorded average (e.g. to start a fresh measurement).
  void reset() {
    _movingDistance = 0;
    _movingSeconds = 0;
    _prevLat = null;
    _prevLng = null;
    _prevTime = null;
    _emit(WalkingSpeedSample.zero);
  }

  /// Feeds one fix and returns the updated sample. Pure (no platform calls).
  WalkingSpeedSample addSample({
    required double lat,
    required double lng,
    required DateTime time,
    double? gpsSpeedMps,
  }) {
    final useGps =
        gpsSpeedMps != null && gpsSpeedMps.isFinite && gpsSpeedMps >= 0;
    var inst = useGps ? gpsSpeedMps : 0.0;

    final prevLat = _prevLat;
    final prevLng = _prevLng;
    final prevTime = _prevTime;
    if (prevLat != null && prevLng != null && prevTime != null) {
      final dt = time.difference(prevTime).inMicroseconds / 1e6;
      if (dt > 0) {
        final dist = _haversineMeters(prevLat, prevLng, lat, lng);
        if (!useGps) inst = dist / dt;
        // Accumulate only genuine, plausible movement into the average.
        if (inst > _movingThresholdMps && inst < _maxPlausibleMps) {
          _movingDistance += dist;
          _movingSeconds += dt;
        }
      }
    }

    _prevLat = lat;
    _prevLng = lng;
    _prevTime = time;

    final avg = _movingSeconds > 0 ? _movingDistance / _movingSeconds : 0.0;
    final moving = inst > _movingThresholdMps;
    final sample = WalkingSpeedSample(
      currentMps: moving ? inst : 0.0,
      averageMps: avg,
      moving: moving,
    );
    _emit(sample);
    return sample;
  }

  void _emit(WalkingSpeedSample sample) {
    _last = sample;
    if (!_controller.isClosed) _controller.add(sample);
  }

  void dispose() {
    stop();
    _controller.close();
  }

  static double _haversineMeters(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    const r = 6371000.0;
    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLng = (lng2 - lng1) * math.pi / 180;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180) *
            math.cos(lat2 * math.pi / 180) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }
}
