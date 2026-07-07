





import 'dart:math' as math;

import 'geo_point.dart';

const double _earthRadiusMeters = 6371000.0;

double _degToRad(double d) => d * math.pi / 180.0;
double _radToDeg(double r) => r * 180.0 / math.pi;


class PolylineProjection {
  
  
  final int segmentIndex;

  
  final GeoPoint projectedPoint;

  
  
  final double distanceAlong;

  
  
  final double crossTrackDistance;

  
  final double t;

  const PolylineProjection({
    required this.segmentIndex,
    required this.projectedPoint,
    required this.distanceAlong,
    required this.crossTrackDistance,
    required this.t,
  });
}

class GeoMath {
  GeoMath._();

  
  static double distanceMeters(GeoPoint a, GeoPoint b) {
    final phi1 = _degToRad(a.latitude);
    final phi2 = _degToRad(b.latitude);
    final dPhi = _degToRad(b.latitude - a.latitude);
    final dLam = _degToRad(b.longitude - a.longitude);
    final h = math.sin(dPhi / 2) * math.sin(dPhi / 2) +
        math.cos(phi1) * math.cos(phi2) * math.sin(dLam / 2) * math.sin(dLam / 2);
    return _earthRadiusMeters * 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h));
  }

  
  static double bearing(GeoPoint a, GeoPoint b) {
    final lat1 = _degToRad(a.latitude);
    final lat2 = _degToRad(b.latitude);
    final dLon = _degToRad(b.longitude - a.longitude);
    final y = math.sin(dLon) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
    return normalizeDegrees(_radToDeg(math.atan2(y, x)));
  }

  
  static double normalizeDegrees(double deg) {
    final m = deg % 360.0;
    return m < 0 ? m + 360.0 : m;
  }

  
  
  
  
  static double signedAngularDifference(double source, double target) {
    var diff = (target - source) % 360.0;
    if (diff < -180.0) diff += 360.0;
    if (diff > 180.0) diff -= 360.0;
    return diff;
  }

  
  static double angularDistance(double a, double b) =>
      signedAngularDifference(a, b).abs();

  
  
  static double? circularMeanDegrees(List<double> anglesDeg) {
    if (anglesDeg.isEmpty) return null;
    var sumSin = 0.0;
    var sumCos = 0.0;
    for (final a in anglesDeg) {
      final r = _degToRad(a);
      sumSin += math.sin(r);
      sumCos += math.cos(r);
    }
    if (sumSin == 0.0 && sumCos == 0.0) return normalizeDegrees(anglesDeg.first);
    return normalizeDegrees(_radToDeg(math.atan2(sumSin, sumCos)));
  }

  
  
  
  
  
  
  
  static PolylineProjection projectOntoPolyline(
    GeoPoint point,
    List<GeoPoint> vertices,
    List<double> cumulative,
  ) {
    assert(vertices.length >= 2, 'polyline needs at least 2 vertices');
    assert(cumulative.length == vertices.length, 'cumulative length mismatch');

    var best = _projectOntoSegment(point, vertices[0], vertices[1]);
    var bestIndex = 0;

    for (var i = 1; i < vertices.length - 1; i++) {
      final candidate = _projectOntoSegment(point, vertices[i], vertices[i + 1]);
      if (candidate.distanceToPoint < best.distanceToPoint) {
        best = candidate;
        bestIndex = i;
      }
    }

    final segmentLength =
        distanceMeters(vertices[bestIndex], vertices[bestIndex + 1]);
    return PolylineProjection(
      segmentIndex: bestIndex,
      projectedPoint: best.projection,
      distanceAlong: cumulative[bestIndex] + best.t * segmentLength,
      crossTrackDistance: best.distanceToPoint,
      t: best.t,
    );
  }

  
  static List<double> cumulativeDistances(List<GeoPoint> vertices) {
    final out = List<double>.filled(vertices.length, 0.0);
    for (var i = 1; i < vertices.length; i++) {
      out[i] = out[i - 1] + distanceMeters(vertices[i - 1], vertices[i]);
    }
    return out;
  }

  
  static _SegmentProjection _projectOntoSegment(
    GeoPoint p,
    GeoPoint a,
    GeoPoint b,
  ) {
    final latRef = _degToRad(a.latitude);
    const metresPerDegLat = 111320.0;
    final metresPerDegLon = 111320.0 * math.cos(latRef);

    double xOf(GeoPoint g) => (g.longitude - a.longitude) * metresPerDegLon;
    double yOf(GeoPoint g) => (g.latitude - a.latitude) * metresPerDegLat;

    const ax = 0.0, ay = 0.0;
    final bx = xOf(b), by = yOf(b);
    final px = xOf(p), py = yOf(p);

    final dx = bx - ax;
    final dy = by - ay;
    final segLenSq = dx * dx + dy * dy;

    double t;
    if (segLenSq == 0.0) {
      t = 0.0;
    } else {
      t = ((px - ax) * dx + (py - ay) * dy) / segLenSq;
      if (t < 0.0) t = 0.0;
      if (t > 1.0) t = 1.0;
    }

    final projLat = a.latitude + (b.latitude - a.latitude) * t;
    final projLon = a.longitude + (b.longitude - a.longitude) * t;
    final projection = GeoPoint(projLat, projLon);

    final cx = ax + dx * t;
    final cy = ay + dy * t;
    final distToPoint =
        math.sqrt((px - cx) * (px - cx) + (py - cy) * (py - cy));

    return _SegmentProjection(projection, t, distToPoint);
  }
}

class _SegmentProjection {
  final GeoPoint projection;
  final double t;
  final double distanceToPoint;
  const _SegmentProjection(this.projection, this.t, this.distanceToPoint);
}
