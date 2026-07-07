import 'package:flutter_test/flutter_test.dart';
import 'package:safenav_app/features/mapbox_navigation/domain/engine/geo_point.dart';
import 'package:safenav_app/features/mapbox_navigation/domain/engine/route_path.dart';

void main() {
  group('RoutePath turn anchoring & classification', () {
    const a = GeoPoint(31.9600, 35.1800);
    const b = GeoPoint(31.9600, 35.1820);
    const c = GeoPoint(31.9620, 35.1820);

    test('significant 90-degree bend is classified as a left turn', () {
      final route = RoutePath.build(
        polyline: const [a, b, c],
        maneuverNodes: const [b],
      );
      expect(route.turns.length, 1);
      final t = route.turns.first;
      expect(t.direction, TurnDirection.left);
      expect(t.vertexIndex, 1);
      expect(t.distanceAlong, closeTo(route.cumulative[1], 1e-6));
      expect(t.turnAngleDeg.abs(), greaterThan(80));
    });

    test('mirror bend is classified as a right turn', () {
      const d = GeoPoint(31.9580, 35.1820);
      final route = RoutePath.build(
        polyline: const [a, b, d],
        maneuverNodes: const [b],
      );
      expect(route.turns.single.direction, TurnDirection.right);
    });

    test('small deviation below threshold is collapsed (no turn)', () {
      const slight = GeoPoint(31.96035, 35.1840);
      final route = RoutePath.build(
        polyline: const [a, b, slight],
        maneuverNodes: const [b],
        significantTurnDegrees: 35,
      );
      expect(route.turns, isEmpty);
    });

    test('anchors a maneuver node to the nearest vertex', () {
      const nearB = GeoPoint(31.96001, 35.18201);
      final route = RoutePath.build(
        polyline: const [a, b, c],
        maneuverNodes: const [nearB],
      );
      expect(route.turns.single.vertexIndex, 1);
    });

    test('start and end nodes never become turns', () {
      final route = RoutePath.build(
        polyline: const [a, b, c],
        maneuverNodes: const [a, c],
      );
      expect(route.turns, isEmpty);
    });

    test('cumulative length and helpers', () {
      final route = RoutePath.build(polyline: const [a, b, c]);
      expect(route.totalLength, greaterThan(0));
      expect(route.destination, c);
      expect((route.segmentBearing(0) - 90).abs(), lessThan(2));
    });

    test('dedupes consecutive duplicate vertices', () {
      final route = RoutePath.build(polyline: const [a, a, b, b, c]);
      expect(route.vertices.length, 3);
    });
  });
}
