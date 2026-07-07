import 'package:flutter_test/flutter_test.dart';
import 'package:safenav_app/features/mapbox_navigation/application/navigation_helpers.dart';

void main() {
  group('pointAheadOnPolyline', () {
    final coords = <List<double>>[
      [31.9600, 35.1820],
      [31.9600, 35.1830], // east segment (~95 m)
      [31.9610, 35.1830], // north segment
    ];

    test('returns a point further along the route (east), bearing ~90', () {
      final p = pointAheadOnPolyline(coords, 0, 31.9600, 35.1820, 10);
      expect(p, isNotNull);
      final b = bearingBetween(31.9600, 35.1820, p![0], p[1]);
      expect(b, closeTo(90, 5));
    });

    test('crosses into the next segment for a longer look-ahead', () {
      // Past the corner the route heads north, so the look-ahead bearing
      // should be between east and north (not a 90° flip artifact).
      final p = pointAheadOnPolyline(coords, 0, 31.9600, 35.1820, 130);
      expect(p, isNotNull);
      // The look-ahead point should be north of the corner latitude.
      expect(p![0], greaterThan(31.9600));
    });

    test('clamps to the route end when the look-ahead exceeds the route', () {
      final p = pointAheadOnPolyline(coords, 0, 31.9600, 35.1820, 100000);
      expect(p, [31.9610, 35.1830]);
    });
  });

  group('projectOntoPolyline', () {
    // A simple route heading roughly east then turning north.
    final coords = <List<double>>[
      [31.9600, 35.1820],
      [31.9600, 35.1830], // east segment
      [31.9610, 35.1830], // north segment
    ];

    test('snaps a point near the first segment and reports east bearing', () {
      // Slightly north of the east-running segment.
      final p = projectOntoPolyline(31.96005, 35.1825, coords)!;
      expect(p.segmentIndex, 0);
      // East is ~90 degrees.
      expect(p.segmentBearing, closeTo(90, 5));
      // Lateral offset should be small (a few meters), not zero.
      expect(p.distanceMeters, lessThan(15));
    });

    test('walking along the edge of the path yields near-zero heading delta',
        () {
      final p = projectOntoPolyline(31.96002, 35.1825, coords)!;
      // A user walking due east (heading 90) on the edge should NOT be told
      // to turn — delta to the segment bearing is tiny.
      final delta = angleDelta(90, p.segmentBearing);
      expect(delta.abs(), lessThan(10));
    });

    test('matches the second segment when past the corner', () {
      final p = projectOntoPolyline(31.9605, 35.18305, coords)!;
      expect(p.segmentIndex, 1);
      // North is ~0/360 degrees.
      final northish = p.segmentBearing < 10 || p.segmentBearing > 350;
      expect(northish, isTrue, reason: 'got ${p.segmentBearing}');
    });

    test('returns null for a degenerate polyline', () {
      expect(projectOntoPolyline(0, 0, [[1, 1]]), isNull);
    });
  });

  group('nearestVertexIndex', () {
    final coords = <List<double>>[
      [31.9600, 35.1820],
      [31.9600, 35.1830],
      [31.9610, 35.1830],
    ];

    test('anchors a maneuver to the closest polyline vertex', () {
      // The right turn happens at the corner vertex (index 1).
      final idx = nearestVertexIndex(31.96001, 35.18299, coords);
      expect(idx, 1);
    });

    test('start maps to first vertex, end to last', () {
      expect(nearestVertexIndex(31.9600, 35.1820, coords), 0);
      expect(nearestVertexIndex(31.9610, 35.1830, coords), 2);
    });
  });

  group('turn phrasing (no slight/sharp tiers)', () {
    test('small deviation stays straight, never "slightly"', () {
      expect(describeTurn(10), 'continue straight ahead');
      expect(describeTurn(30), 'continue straight ahead');
      expect(describeTurn(-30), 'continue straight ahead');
    });

    test('genuine turn is a plain left/right', () {
      expect(describeTurn(90), 'turn right');
      expect(describeTurn(-90), 'turn left');
    });

    test('reversal is turn around', () {
      expect(describeTurn(170), 'turn around');
    });

    test('no phrase ever contains "slight" or "sharp"', () {
      for (var d = -180; d <= 180; d += 5) {
        final p = describeTurn(d.toDouble());
        expect(p.contains('slight'), isFalse, reason: 'delta=$d -> $p');
        expect(p.contains('sharp'), isFalse, reason: 'delta=$d -> $p');
      }
    });

    test('modifier mapping collapses slight to straight, sharp to turn', () {
      expect(modifierToPhrase('slight left'), 'continue straight ahead');
      expect(modifierToPhrase('slight right'), 'continue straight ahead');
      expect(modifierToPhrase('sharp left'), 'turn left');
      expect(modifierToPhrase('sharp right'), 'turn right');
      expect(modifierToPhrase('left'), 'turn left');
      expect(modifierToPhrase('right'), 'turn right');
    });

    test('isTurnInstruction distinguishes turns from going straight', () {
      expect(isTurnInstruction('turn left'), isTrue);
      expect(isTurnInstruction('turn around'), isTrue);
      expect(isTurnInstruction('continue straight ahead'), isFalse);
    });
  });

  group('alignment phrasing', () {
    test('no correction inside the deadzone', () {
      expect(describeAlignmentCorrection(10), isNull);
      expect(describeAlignmentCorrection(30), isNull);
    });

    test('large delta produces a turn-to-face-path instruction', () {
      expect(describeAlignmentCorrection(90), 'turn right to face the path');
      expect(describeAlignmentCorrection(-90), 'turn left to face the path');
    });

    test('correction never contains "slight"', () {
      for (var d = -180; d <= 180; d += 5) {
        final p = describeAlignmentCorrection(d.toDouble());
        if (p != null) {
          expect(p.contains('slight'), isFalse, reason: 'delta=$d -> $p');
        }
      }
    });
  });
}
