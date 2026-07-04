

















import 'geo_math.dart';
import 'geo_point.dart';
import 'nav_instruction.dart';
import 'route_path.dart';


class NavUpdate {
  final NavInstruction? instruction;
  final PolylineProjection projection;
  final double segmentBearing;
  final double distanceToNext;
  final bool arrived;

  const NavUpdate({
    required this.instruction,
    required this.projection,
    required this.segmentBearing,
    required this.distanceToNext,
    required this.arrived,
  });
}

class NavEngineConfig {
  final Duration speechCooldown;
  final double reachableWindowMeters;
  final double arrivalRadiusMeters;
  final double orientationDeadzoneDeg;
  final double turnAroundThresholdDeg;

  
  
  
  final double orientationApproachMeters;

  
  
  final Duration orientationSettle;

  
  
  
  
  
  final double continueDistanceChangeMeters;

  const NavEngineConfig({
    this.speechCooldown = const Duration(seconds: 5),
    this.reachableWindowMeters = 4.0,
    this.arrivalRadiusMeters = 5.5,
    this.orientationDeadzoneDeg = 45.0,
    this.turnAroundThresholdDeg = 135.0,
    this.orientationApproachMeters = 12.0,
    this.orientationSettle = const Duration(seconds: 5),
    this.continueDistanceChangeMeters = 5.0,
  });
}

class NavEngine {
  final RoutePath route;
  final NavEngineConfig config;

  int _nextTurnIndex = 0;
  NavInstruction? _lastSpoken;
  DateTime? _lastSpeakTime;
  DateTime? _lastTurnAt;
  bool _arrived = false;

  NavEngine(this.route, {this.config = const NavEngineConfig()});

  bool get arrived => _arrived;
  int get nextTurnIndex => _nextTurnIndex;
  int get turnCount => route.turns.length;
  NavInstruction? get lastSpoken => _lastSpoken;

  
  
  NavUpdate update({
    required GeoPoint position,
    double? heading,
    bool headingStable = false,
    required DateTime now,
  }) {
    final proj = route.project(position);
    final segBearing = route.segmentBearing(proj.segmentIndex);
    final userAlong = proj.distanceAlong;

    final activeTurn = _activeTurn;
    final hasTurnAhead = activeTurn != null;
    final remainingToTurn =
        hasTurnAhead ? (activeTurn.distanceAlong - userAlong) : double.infinity;
    final remainingToDest = (route.totalLength - userAlong);
    final distanceToNext = (hasTurnAhead ? remainingToTurn : remainingToDest)
        .clamp(0.0, double.infinity);

    if (_arrived) {
      return NavUpdate(
        instruction: null,
        projection: proj,
        segmentBearing: segBearing,
        distanceToNext: 0,
        arrived: true,
      );
    }

    
    final distToDest = GeoMath.distanceMeters(position, route.destination);
    if (distToDest <= config.arrivalRadiusMeters ||
        remainingToDest <= config.arrivalRadiusMeters) {
      _arrived = true;
      final inst = _commit(NavPhrasing.arrival(), now);
      return NavUpdate(
        instruction: inst,
        projection: proj,
        segmentBearing: segBearing,
        distanceToNext: 0,
        arrived: true,
      );
    }

    
    if (hasTurnAhead) {
      final reached = remainingToTurn <= config.reachableWindowMeters;
      final passed = userAlong >= activeTurn.distanceAlong;
      if (reached || passed) {
        _nextTurnIndex++;
        _lastTurnAt = now;
        final inst = _commit(NavPhrasing.turn(activeTurn.direction), now);
        return NavUpdate(
          instruction: inst,
          projection: proj,
          segmentBearing: segBearing,
          distanceToNext: _distanceToNextAfterAdvance(userAlong),
          arrived: false,
        );
      }
    }

    
    
    
    
    
    final nearTurn =
        hasTurnAhead && remainingToTurn <= config.orientationApproachMeters;
    final settling = _lastTurnAt != null &&
        now.difference(_lastTurnAt!) < config.orientationSettle;
    if (headingStable && heading != null && !nearTurn && !settling) {
      final delta = GeoMath.signedAngularDifference(heading, segBearing);
      final absDelta = delta.abs();
      if (absDelta > config.orientationDeadzoneDeg) {
        final FacingCorrection correction;
        if (absDelta > config.turnAroundThresholdDeg) {
          correction = FacingCorrection.turnAround;
        } else if (delta > 0) {
          correction = FacingCorrection.turnRight;
        } else {
          correction = FacingCorrection.turnLeft;
        }
        final inst = _commit(NavPhrasing.orientation(correction), now);
        return NavUpdate(
          instruction: inst,
          projection: proj,
          segmentBearing: segBearing,
          distanceToNext: distanceToNext,
          arrived: false,
        );
      }
    }

    
    final isFinalLeg = !hasTurnAhead;
    final inst = _commit(
      NavPhrasing.continueStraight(distanceToNext, isFinalLeg: isFinalLeg),
      now,
    );
    return NavUpdate(
      instruction: inst,
      projection: proj,
      segmentBearing: segBearing,
      distanceToNext: distanceToNext,
      arrived: false,
    );
  }

  RouteManeuver? get _activeTurn =>
      _nextTurnIndex < route.turns.length ? route.turns[_nextTurnIndex] : null;

  double _distanceToNextAfterAdvance(double userAlong) {
    final next = _activeTurn;
    final raw = (next != null)
        ? next.distanceAlong - userAlong
        : route.totalLength - userAlong;
    return raw < 0 ? 0.0 : raw;
  }

  
  
  NavInstruction? _commit(NavInstruction inst, DateTime now) {
    
    
    
    if (inst.isCritical) {
      _lastSpoken = inst;
      _lastSpeakTime = now;
      return inst;
    }

    
    
    if (_lastSpoken == inst) {
      return null;
    }

    
    if (_lastSpeakTime != null &&
        now.difference(_lastSpeakTime!) < config.speechCooldown) {
      return null;
    }

    
    
    
    
    if (inst.kind == NavInstructionKind.continueStraight &&
        _lastSpoken?.kind == NavInstructionKind.continueStraight) {
      final lastD = _lastSpoken?.distanceMeters;
      final newD = inst.distanceMeters;
      if (lastD != null &&
          newD != null &&
          (lastD - newD).abs() < config.continueDistanceChangeMeters) {
        return null;
      }
    }

    _lastSpoken = inst;
    _lastSpeakTime = now;
    return inst;
  }
}
