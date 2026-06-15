import 'dart:math' as math;

double bearingBetween(
  double lat1,
  double lng1,
  double lat2,
  double lng2,
) {
  final phi1 = lat1 * math.pi / 180;
  final phi2 = lat2 * math.pi / 180;
  final dLambda = (lng2 - lng1) * math.pi / 180;

  final y = math.sin(dLambda) * math.cos(phi2);
  final x = math.cos(phi1) * math.sin(phi2) -
      math.sin(phi1) * math.cos(phi2) * math.cos(dLambda);

  final theta = math.atan2(y, x);
  return ((theta * 180 / math.pi) + 360) % 360;
}

double angleDelta(double from, double to) {
  double diff = to - from;
  while (diff > 180) {
    diff -= 360;
  }
  while (diff <= -180) {
    diff += 360;
  }
  return diff;
}

double distancePointToSegmentMeters(
  double pLat,
  double pLng,
  double aLat,
  double aLng,
  double bLat,
  double bLng,
) {
  final lat0 = (aLat + bLat) / 2.0;
  const mPerDegLat = 111320.0;
  final mPerDegLng = 111320.0 * math.cos(lat0 * math.pi / 180);

  final px = pLng * mPerDegLng;
  final py = pLat * mPerDegLat;
  final ax = aLng * mPerDegLng;
  final ay = aLat * mPerDegLat;
  final bx = bLng * mPerDegLng;
  final by = bLat * mPerDegLat;

  final dx = bx - ax;
  final dy = by - ay;
  final lenSq = dx * dx + dy * dy;

  if (lenSq < 1e-9) {
    final ddx = px - ax;
    final ddy = py - ay;
    return math.sqrt(ddx * ddx + ddy * ddy);
  }

  double t = ((px - ax) * dx + (py - ay) * dy) / lenSq;
  if (t < 0) t = 0;
  if (t > 1) t = 1;

  final ex = ax + t * dx;
  final ey = ay + t * dy;
  final ddx = px - ex;
  final ddy = py - ey;
  return math.sqrt(ddx * ddx + ddy * ddy);
}

double distancePointToPolylineMeters(
  double pLat,
  double pLng,
  List<List<double>> coords,
) {
  if (coords.isEmpty) return double.infinity;
  if (coords.length == 1) {
    return _haversineMeters(pLat, pLng, coords[0][0], coords[0][1]);
  }
  double minDist = double.infinity;
  for (int i = 0; i < coords.length - 1; i++) {
    final d = distancePointToSegmentMeters(
      pLat,
      pLng,
      coords[i][0],
      coords[i][1],
      coords[i + 1][0],
      coords[i + 1][1],
    );
    if (d < minDist) minDist = d;
  }
  return minDist;
}

/// Result of projecting a point onto a polyline.
class PolylineProjection {
  const PolylineProjection({
    required this.segmentIndex,
    required this.distanceMeters,
    required this.segmentBearing,
    required this.snappedLat,
    required this.snappedLng,
  });

  /// Index of the segment [i, i+1] the point projected onto.
  final int segmentIndex;

  /// Perpendicular distance from the point to the route, in meters.
  final double distanceMeters;

  /// Bearing of the matched segment (the direction the user *should* face),
  /// in degrees 0..360.
  final double segmentBearing;

  final double snappedLat;
  final double snappedLng;
}

/// Projects a GPS point onto a route polyline and returns the closest segment,
/// its bearing, and the snapped point.
///
/// This is what makes guidance "path-relative": instead of pointing the user
/// at the next maneuver node (which is wrong when walking along the edge of a
/// wide path), we align them with the direction of the route segment they are
/// currently on.
PolylineProjection? projectOntoPolyline(
  double pLat,
  double pLng,
  List<List<double>> coords,
) {
  if (coords.length < 2) return null;

  const mPerDegLat = 111320.0;
  double bestDist = double.infinity;
  int bestIdx = 0;
  double bestLat = pLat;
  double bestLng = pLng;

  for (int i = 0; i < coords.length - 1; i++) {
    final aLat = coords[i][0];
    final aLng = coords[i][1];
    final bLat = coords[i + 1][0];
    final bLng = coords[i + 1][1];

    final lat0 = (aLat + bLat) / 2.0;
    final mPerDegLng = mPerDegLat * math.cos(lat0 * math.pi / 180);

    final px = pLng * mPerDegLng;
    final py = pLat * mPerDegLat;
    final ax = aLng * mPerDegLng;
    final ay = aLat * mPerDegLat;
    final bx = bLng * mPerDegLng;
    final by = bLat * mPerDegLat;

    final dx = bx - ax;
    final dy = by - ay;
    final lenSq = dx * dx + dy * dy;

    double t = lenSq < 1e-9 ? 0 : ((px - ax) * dx + (py - ay) * dy) / lenSq;
    if (t < 0) t = 0;
    if (t > 1) t = 1;

    final ex = ax + t * dx;
    final ey = ay + t * dy;
    final ddx = px - ex;
    final ddy = py - ey;
    final dist = math.sqrt(ddx * ddx + ddy * ddy);

    if (dist < bestDist) {
      bestDist = dist;
      bestIdx = i;
      bestLng = ex / mPerDegLng;
      bestLat = ey / mPerDegLat;
    }
  }

  final bearing = bearingBetween(
    coords[bestIdx][0],
    coords[bestIdx][1],
    coords[bestIdx + 1][0],
    coords[bestIdx + 1][1],
  );

  return PolylineProjection(
    segmentIndex: bestIdx,
    distanceMeters: bestDist,
    segmentBearing: bearing,
    snappedLat: bestLat,
    snappedLng: bestLng,
  );
}

double _haversineMeters(
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
  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return r * c;
}

String describeTurn(double delta) {
  final abs = delta.abs();
  if (abs < 20) return 'continue straight';
  if (abs < 60) {
    return delta > 0 ? 'turn slightly right' : 'turn slightly left';
  }
  if (abs < 135) {
    return delta > 0 ? 'turn right' : 'turn left';
  }
  if (abs < 160) {
    return delta > 0 ? 'turn sharply right' : 'turn sharply left';
  }
  return 'turn around';
}

String? describeAlignmentCorrection(double delta) {
  final abs = delta.abs();
  if (abs < 25) return null;
  if (abs < 60) {
    return delta > 0 ? 'adjust slightly right' : 'adjust slightly left';
  }
  if (abs < 135) {
    return delta > 0 ? 'turn right to face the path' : 'turn left to face the path';
  }
  return 'turn around to face the path';
}

String initialDirectionPhrase(double delta) {
  final abs = delta.abs();
  if (abs < 20) return 'Walk straight forward';
  if (abs < 60) {
    return delta > 0
        ? 'Turn slightly right and walk forward'
        : 'Turn slightly left and walk forward';
  }
  if (abs < 135) {
    return delta > 0
        ? 'Turn right and walk forward'
        : 'Turn left and walk forward';
  }
  if (abs < 160) {
    return delta > 0
        ? 'Turn sharply right and walk forward'
        : 'Turn sharply left and walk forward';
  }
  return 'Turn around and walk forward';
}

String modifierToPhrase(String? modifier, {String fallbackType = ''}) {
  switch (modifier) {
    case 'left':
      return 'turn left';
    case 'right':
      return 'turn right';
    case 'slight left':
      return 'turn slightly left';
    case 'slight right':
      return 'turn slightly right';
    case 'sharp left':
      return 'turn sharply left';
    case 'sharp right':
      return 'turn sharply right';
    case 'straight':
      return 'continue straight';
    case 'uturn':
      return 'turn around';
  }
  switch (fallbackType) {
    case 'arrive':
      return 'arrive at destination';
    case 'depart':
      return 'begin walking';
    case 'continue':
      return 'continue straight';
    case 'turn':
      return 'turn';
    default:
      return 'continue';
  }
}

String capitalizeFirst(String s) {
  if (s.isEmpty) return s;
  return s[0].toUpperCase() + s.substring(1);
}
