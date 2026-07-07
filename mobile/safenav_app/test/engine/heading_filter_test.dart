import 'package:flutter_test/flutter_test.dart';
import 'package:safenav_app/features/mapbox_navigation/domain/engine/geo_math.dart';
import 'package:safenav_app/features/mapbox_navigation/domain/engine/heading_filter.dart';

void main() {
  group('HeadingFilter circular averaging', () {
    test('averages across the 0/360 wrap-around', () {
      final f = HeadingFilter(
        windowSize: 4,
        stabilityToleranceDeg: 20,
        requiredStableSamples: 2,
      );
      f.add(350);
      f.add(10);
      f.add(350);
      final est = f.add(10);
      expect(est.smoothedHeading, isNotNull);
      expect(GeoMath.angularDistance(est.smoothedHeading!, 0), lessThan(5));
    });

    test('plain mean for tight cluster', () {
      final f = HeadingFilter(windowSize: 5, requiredStableSamples: 1);
      f.add(88);
      f.add(90);
      final est = f.add(92);
      expect(GeoMath.angularDistance(est.smoothedHeading!, 90), lessThan(2));
    });
  });

  group('HeadingFilter stability gate', () {
    test('not stable until enough consecutive agreeing samples', () {
      final f = HeadingFilter(
        windowSize: 6,
        stabilityToleranceDeg: 10,
        requiredStableSamples: 4,
      );
      expect(f.add(100).isStable, isFalse);
      expect(f.add(101).isStable, isFalse);
      expect(f.add(99).isStable, isFalse);
      expect(f.add(100).isStable, isTrue);
      expect(f.add(101).isStable, isTrue);
    });

    test('a wild jump resets stability', () {
      final f = HeadingFilter(
        windowSize: 6,
        stabilityToleranceDeg: 10,
        requiredStableSamples: 3,
        jumpResetThresholdDeg: 45,
      );
      f.add(90);
      f.add(91);
      expect(f.add(90).isStable, isTrue);

      final afterJump = f.add(210);
      expect(afterJump.isStable, isFalse);
      expect(GeoMath.angularDistance(afterJump.smoothedHeading!, 210),
          lessThan(5));

      f.add(211);
      expect(f.add(209).isStable, isTrue);
    });

    test('current reflects state without adding a sample', () {
      final f = HeadingFilter(requiredStableSamples: 2);
      expect(f.current.isStable, isFalse);
      expect(f.current.smoothedHeading, isNull);
      f.add(45);
      f.add(46);
      expect(f.current.isStable, isTrue);
    });

    test('reset clears history', () {
      final f = HeadingFilter(requiredStableSamples: 1);
      f.add(30);
      expect(f.current.smoothedHeading, isNotNull);
      f.reset();
      expect(f.current.smoothedHeading, isNull);
      expect(f.current.isStable, isFalse);
    });
  });
}
