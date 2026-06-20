// Builds a navigable route model from a raw polyline and a set of candidate
// maneuver nodes (e.g. the Directions API step boundaries).
//
// Responsibilities:
//   * Clean the polyline vertices and compute cumulative along-route distances.
//   * Anchor each maneuver node to the nearest polyline vertex.
//   * Classify the turn at each anchor from the geometry (bearing change),
//     keeping ONLY significant turns. Small deviations are collapsed (the
//     engine speaks "continue straight ahead" through them). No notion of
//     "slight" or "sharp" exists here.
//
// Pure Dart, no Flutter/SDK dependencies. Ported from the Google-nav engine.

import 'geo_math.dart';
import 'geo_point.dart';

enum TurnDirection { left, right, straight }

/// A significant turn anchored to a vertex on the route polyline.
class RouteManeuver {
  final int vertexIndex;
  final GeoPoint location;
  final double distanceAlong;
  final TurnDirection direction;
  final double turnAngleDeg;

  const RouteManeuver({
    required this.vertexIndex,
    required this.location,
    required this.distanceAlong,
    required this.direction,
    required this.turnAngleDeg,
  });
}

class RoutePath {
  /// Cleaned polyline vertices (consecutive duplicates removed).
  final List<GeoPoint> vertices;

  /// Cumulative along-route distance at each vertex (metres). cumulative[0]==0.
  final List<double> cumulative;

  /// Significant turns only, ordered by [RouteManeuver.distanceAlong].
  final List<RouteManeuver> turns;

  RoutePath._(this.vertices, this.cumulative, this.turns);

  double get totalLength => cumulative.isEmpty ? 0.0 : cumulative.last;

  GeoPoint get destination => vertices.last;

  PolylineProjection project(GeoPoint point) =>
      GeoMath.projectOntoPolyline(point, vertices, cumulative);

  /// Bearing of the segment starting at vertex [index].
  double segmentBearing(int index) {
    final i = index.clamp(0, vertices.length - 2);
    return GeoMath.bearing(vertices[i], vertices[i + 1]);
  }

  static RoutePath build({
    required List<GeoPoint> polyline,
    List<GeoPoint> maneuverNodes = const [],
    double significantTurnDegrees = 35.0,
  }) {
    final vertices = _dedupe(polyline);
    if (vertices.length < 2) {
      final cumulative = GeoMath.cumulativeDistances(vertices);
      return RoutePath._(vertices, cumulative, const []);
    }

    final cumulative = GeoMath.cumulativeDistances(vertices);

    final turns = <RouteManeuver>[];
    final seenVertices = <int>{};

    for (final node in maneuverNodes) {
      final anchor = _nearestVertexIndex(node, vertices);
      // A turn needs a segment on both sides; start/destination are separate.
      if (anchor <= 0 || anchor >= vertices.length - 1) continue;
      if (!seenVertices.add(anchor)) continue;

      final incoming = GeoMath.bearing(vertices[anchor - 1], vertices[anchor]);
      final outgoing = GeoMath.bearing(vertices[anchor], vertices[anchor + 1]);
      final delta = GeoMath.signedAngularDifference(incoming, outgoing);

      if (delta.abs() < significantTurnDegrees) {
        continue; // collapse small deviation -> stays "continue straight ahead"
      }

      turns.add(RouteManeuver(
        vertexIndex: anchor,
        location: vertices[anchor],
        distanceAlong: cumulative[anchor],
        direction: delta > 0 ? TurnDirection.right : TurnDirection.left,
        turnAngleDeg: delta,
      ));
    }

    turns.sort((a, b) => a.distanceAlong.compareTo(b.distanceAlong));
    return RoutePath._(vertices, cumulative, turns);
  }

  static List<GeoPoint> _dedupe(List<GeoPoint> pts) {
    final out = <GeoPoint>[];
    for (final p in pts) {
      if (out.isEmpty || out.last != p) out.add(p);
    }
    return out;
  }

  static int _nearestVertexIndex(GeoPoint node, List<GeoPoint> vertices) {
    var bestIndex = 0;
    var bestDist = double.infinity;
    for (var i = 0; i < vertices.length; i++) {
      final d = GeoMath.distanceMeters(node, vertices[i]);
      if (d < bestDist) {
        bestDist = d;
        bestIndex = i;
      }
    }
    return bestIndex;
  }
}
