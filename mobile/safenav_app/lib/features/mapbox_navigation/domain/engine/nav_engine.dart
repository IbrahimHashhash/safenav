// Position-relative TTS guidance engine for blind navigation.
//
// One instruction is derived per location/heading event from the user's
// position PROJECTED onto the route polyline:
//   * Distances are measured ALONG the route, so "continue" stays correct
//     around curves and decreases as the user advances.
//   * A single global cooldown (<= 5 s) gates non-critical speech; turns and
//     arrival are critical and bypass it. Identical consecutive lines are
//     de-duplicated.
//   * Robust turn progression: each turn is anchored to a polyline vertex; the
//     turn fires when the user is within a small REACHABLE window OR has passed
//     the anchor. Passing a maneuver ALWAYS advances the pointer.
//   * Path-relative orientation: the direction to face comes from the bearing
//     of the CURRENT route segment, not the straight-line bearing to the next
//     node. A deadzone suppresses corrections when essentially aligned.
//
// Pure Dart, no Flutter/SDK dependencies. Ported from the Google-nav engine.

import 'geo_math.dart';
import 'geo_point.dart';
import 'nav_instruction.dart';
import 'route_path.dart';

/// Result of feeding one location/heading event to the engine.
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

  /// Orientation corrections are suppressed when the user is within this
  /// distance (m) of the next turn — the maneuver instruction handles the turn,
  /// and the compass-vs-segment-bearing reading is unreliable at a corner.
  final double orientationApproachMeters;

  /// Orientation corrections are also suppressed for this long AFTER a turn
  /// fires, while the user is completing the turn (heading still settling).
  final Duration orientationSettle;

  /// "Continue straight ahead" is re-announced only once the remaining distance
  /// has changed by at least this much (meters). Smaller drifts are not
  /// repeated, so the user isn't told a slightly different distance every few
  /// seconds; larger progress (e.g. 20 m -> 10 m) is announced. Turns and
  /// arrival are unaffected (they are always spoken).
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

  /// Feeds one event. [heading] is the smoothed compass heading (degrees);
  /// [headingStable] must be true before orientation corrections are allowed.
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

    // 1) Arrival (critical).
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

    // 2) Turn progression (critical). Fire when reached OR passed.
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

    // 3) Orientation correction (non-critical), only on a stable heading.
    //    Suppressed near a turn and just after one: there the maneuver handles
    //    guidance and the compass-vs-segment-bearing reading flips at the
    //    corner, which would otherwise contradict the turn ("turn left" + an
    //    opposite "turn right to face the path").
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

    // 4) Continue straight ahead (non-critical), distance along the route.
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

  /// Applies cooldown (non-critical only), de-duplication, and distance-aware
  /// gating of "continue straight".
  NavInstruction? _commit(NavInstruction inst, DateTime now) {
    // Turns and arrival are critical: they mark a real maneuver and must NEVER
    // be suppressed as redundant — e.g. two left turns in a row must both be
    // spoken, and a turn is never dropped just because distance barely changed.
    if (inst.isCritical) {
      _lastSpoken = inst;
      _lastSpeakTime = now;
      return inst;
    }

    // Exact same non-critical line as the previous one → don't repeat it
    // back-to-back.
    if (_lastSpoken == inst) {
      return null;
    }

    // Non-critical lines are rate-limited by the cooldown.
    if (_lastSpeakTime != null &&
        now.difference(_lastSpeakTime!) < config.speechCooldown) {
      return null;
    }

    // "Continue straight" repeats only on a MEANINGFUL distance change. Even
    // after the cooldown, a drift smaller than the threshold is not repeated
    // (so the user isn't told a slightly different distance every few seconds);
    // it is re-announced once they have made real progress along the route.
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
