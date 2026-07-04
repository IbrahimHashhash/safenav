import 'package:flutter_test/flutter_test.dart';
import 'package:safenav_app/core/services/location/walking_speed_tracker.dart';

void main() {
  group('WalkingSpeedTracker.addSample', () {
    test('first sample has no speed (no previous fix)', () {
      final t = WalkingSpeedTracker();
      final s = t.addSample(
        lat: 0,
        lng: 0,
        time: DateTime(2026, 1, 1, 12, 0, 0),
      );
      expect(s.currentMps, 0);
      expect(s.averageMps, 0);
      expect(s.moving, isFalse);
    });

    test('computes current + average from displacement when no GPS speed', () {
      final t = WalkingSpeedTracker();
      final t0 = DateTime(2026, 1, 1, 12, 0, 0);
      t.addSample(lat: 0, lng: 0, time: t0);
      // ~1.11 m east over 1 s (0.00001 deg lng at the equator).
      final s = t.addSample(
        lat: 0,
        lng: 0.00001,
        time: t0.add(const Duration(seconds: 1)),
      );
      expect(s.moving, isTrue);
      expect(s.currentMps, closeTo(1.11, 0.2));
      expect(s.averageMps, closeTo(1.11, 0.2));
    });

    test('uses the GPS speed for current when provided', () {
      final t = WalkingSpeedTracker();
      final t0 = DateTime(2026, 1, 1, 12, 0, 0);
      t.addSample(lat: 0, lng: 0, time: t0, gpsSpeedMps: 0);
      final s = t.addSample(
        lat: 0,
        lng: 0.00001,
        time: t0.add(const Duration(seconds: 1)),
        gpsSpeedMps: 1.4,
      );
      expect(s.currentMps, closeTo(1.4, 1e-9));
      expect(s.averageMps, greaterThan(0)); // displacement-based average
      expect(s.moving, isTrue);
    });

    test('stopping shows current 0 but RETAINS the recorded average', () {
      final t = WalkingSpeedTracker();
      final t0 = DateTime(2026, 1, 1, 12, 0, 0);
      t.addSample(lat: 0, lng: 0, time: t0);
      final walking = t.addSample(
        lat: 0,
        lng: 0.00002,
        time: t0.add(const Duration(seconds: 1)),
      );
      expect(walking.averageMps, greaterThan(0));

      // Same spot, 1s later, GPS reports ~0 => stopped.
      final stopped = t.addSample(
        lat: 0,
        lng: 0.00002,
        time: t0.add(const Duration(seconds: 2)),
        gpsSpeedMps: 0,
      );
      expect(stopped.moving, isFalse);
      expect(stopped.currentMps, 0);
      expect(stopped.averageMps, closeTo(walking.averageMps, 1e-9));
    });

    test('reset clears the recorded average', () {
      final t = WalkingSpeedTracker();
      final t0 = DateTime(2026, 1, 1, 12, 0, 0);
      t.addSample(lat: 0, lng: 0, time: t0);
      t.addSample(
        lat: 0,
        lng: 0.00002,
        time: t0.add(const Duration(seconds: 1)),
      );
      t.reset();
      expect(t.current.averageMps, 0);
      expect(t.current.currentMps, 0);
    });
  });
}
