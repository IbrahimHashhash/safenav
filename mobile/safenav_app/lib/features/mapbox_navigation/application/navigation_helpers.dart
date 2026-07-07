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


class PolylineProjection {
  const PolylineProjection({
    required this.segmentIndex,
    required this.distanceMeters,
    required this.segmentBearing,
    required this.snappedLat,
    required this.snappedLng,
  });

  
  final int segmentIndex;

  
  final double distanceMeters;

  
  
  final double segmentBearing;

  final double snappedLat;
  final double snappedLng;
}








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




int nearestVertexIndex(
  double lat,
  double lng,
  List<List<double>> coords,
) {
  int bestIdx = 0;
  double bestSq = double.infinity;
  for (int i = 0; i < coords.length; i++) {
    final dLat = coords[i][0] - lat;
    final dLng = coords[i][1] - lng;
    final sq = dLat * dLat + dLng * dLng;
    if (sq < bestSq) {
      bestSq = sq;
      bestIdx = i;
    }
  }
  return bestIdx;
}







List<double>? pointAheadOnPolyline(
  List<List<double>> coords,
  int segmentIndex,
  double snappedLat,
  double snappedLng,
  double aheadMeters,
) {
  if (coords.length < 2) return null;
  var remaining = aheadMeters;
  var curLat = snappedLat;
  var curLng = snappedLng;
  final start = segmentIndex.clamp(0, coords.length - 2);

  for (int i = start; i < coords.length - 1; i++) {
    final nLat = coords[i + 1][0];
    final nLng = coords[i + 1][1];
    final segLen = _haversineMeters(curLat, curLng, nLat, nLng);
    if (segLen >= remaining) {
      final f = segLen < 1e-9 ? 1.0 : remaining / segLen;
      return [curLat + (nLat - curLat) * f, curLng + (nLng - curLng) * f];
    }
    remaining -= segLen;
    curLat = nLat;
    curLng = nLng;
  }
  return [coords.last[0], coords.last[1]];
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




const double kStraightThresholdDeg = 45.0;


const double kUTurnThresholdDeg = 150.0;

String describeTurn(double delta) {
  final abs = delta.abs();
  if (abs < kStraightThresholdDeg) return 'continue straight ahead';
  if (abs < kUTurnThresholdDeg) {
    return delta > 0 ? 'turn right' : 'turn left';
  }
  return 'turn around';
}

String? describeAlignmentCorrection(double delta) {
  final abs = delta.abs();
  if (abs < kStraightThresholdDeg) return null;
  if (abs < kUTurnThresholdDeg) {
    return delta > 0
        ? 'turn right to face the path'
        : 'turn left to face the path';
  }
  return 'turn around to face the path';
}

String initialDirectionPhrase(double delta) {
  final abs = delta.abs();
  if (abs < kStraightThresholdDeg) return 'Walk straight ahead';
  if (abs < kUTurnThresholdDeg) {
    return delta > 0
        ? 'Turn right and walk forward'
        : 'Turn left and walk forward';
  }
  return 'Turn around and walk forward';
}

String modifierToPhrase(String? modifier, {String fallbackType = ''}) {
  switch (modifier) {
    case 'left':
    case 'sharp left':
      return 'turn left';
    case 'right':
    case 'sharp right':
      return 'turn right';
    case 'slight left':
    case 'slight right':
    case 'straight':
      
      return 'continue straight ahead';
    case 'uturn':
      return 'turn around';
  }
  switch (fallbackType) {
    case 'arrive':
      return 'arrive at destination';
    case 'depart':
      return 'begin walking';
    case 'continue':
      return 'continue straight ahead';
    default:
      return 'continue straight ahead';
  }
}


bool isTurnInstruction(String phrase) => phrase.startsWith('turn');

String capitalizeFirst(String s) {
  if (s.isEmpty) return s;
  return s[0].toUpperCase() + s.substring(1);
}
