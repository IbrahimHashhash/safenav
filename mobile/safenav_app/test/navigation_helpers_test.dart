import 'package:flutter_test/flutter_test.dart';
import 'package:safenav_app/features/mapbox_navigation/application/navigation_helpers.dart';

void main() {
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

  group('alignment phrasing', () {
    test('no correction inside the deadzone', () {
      expect(describeAlignmentCorrection(10), isNull);
    });

    test('large delta produces a turn-to-face-path instruction', () {
      expect(describeAlignmentCorrection(90), contains('right'));
      expect(describeAlignmentCorrection(-90), contains('left'));
    });
  });
}
