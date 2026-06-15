import 'package:flutter_test/flutter_test.dart';
import 'package:safenav_app/features/mapbox_navigation/application/heading_filter.dart';

void main() {
  group('HeadingFilter', () {
    test('reports unstable until enough agreeing samples arrive', () {
      final filter = HeadingFilter(requiredStableSamples: 3);
      filter.addSample(90);
      expect(filter.isStable, isFalse);
      filter.addSample(92);
      filter.addSample(88);
      expect(filter.isStable, isTrue);
    });

    test('resets stability when a sample jumps wildly (noise rejection)', () {
      final filter = HeadingFilter(
        requiredStableSamples: 3,
        stabilityToleranceDeg: 25,
      );
      filter.addSample(90);
      filter.addSample(91);
      filter.addSample(89);
      expect(filter.isStable, isTrue);

      // A spurious 180-degree jump should drop stability.
      filter.addSample(270);
      expect(filter.isStable, isFalse);
    });

    test('smooths toward the signal without overshooting across wrap-around',
        () {
      final filter = HeadingFilter(smoothingFactor: 0.5);
      // Average of 350 and 10 along the short arc is ~0/360, not 180.
      filter.addSample(350);
      final result = filter.addSample(10);
      expect(result, isNotNull);
      final h = result!;
      final nearZero = h < 5 || h > 355;
      expect(nearZero, isTrue, reason: 'expected ~0, got $h');
    });

    test('returns null when readings are stale', () {
      final filter = HeadingFilter(maxSampleAge: Duration.zero);
      filter.addSample(123);
      expect(filter.smoothedHeading, isNull);
    });
  });
}
