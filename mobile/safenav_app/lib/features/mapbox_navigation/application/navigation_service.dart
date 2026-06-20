import 'dart:async';

import 'package:geolocator/geolocator.dart';

import '../../../core/services/compass/compass_service.dart';
import '../../../shared/models/location.dart';
import '../domain/entities/navigation_snapshot.dart';
import '../domain/entities/route_entity.dart';
import '../domain/entities/turn_by_turn_step.dart';
import '../domain/usecases/get_route_usecase.dart';
import 'heading_filter.dart';
import 'navigation_helpers.dart';

/// Pedestrian turn-by-turn navigation engine.
///
/// Guidance is **position-relative**: instructions are derived from the user's
/// current location projected onto the route, and a single announcement is
/// emitted per meaningful event. A global cooldown prevents the engine from
/// stacking conflicting instructions while the user is standing still.
class NavigationService {
  // --- Geometry / timing tuning ---------------------------------------------

  /// Window (meters of remaining distance to the maneuver) within which the
  /// turn instruction ("turn left") fires. Small enough to feel "at the turn",
  /// but large enough to be reachable given GPS sampling (~2 m) and the fact
  /// that you round corners on a curve rather than crossing the exact maneuver
  /// point. The maneuver is also force-completed once you pass its polyline
  /// vertex, so a missed trigger never strands the engine.
  static const double _maneuverTriggerDistance = 6.0;

  /// Distance (meters) at which arrival is announced. Kept comfortably above
  /// typical pedestrian GPS error so "you have arrived" actually fires.
  static const double _arrivalThreshold = 12.0;
  static const double _offRouteThreshold = 25.0;
  static const int _offRouteFixesRequired = 3;

  static const Duration _readyDelay = Duration(seconds: 3);

  /// Global cooldown between *any* two spoken instructions. Keeps guidance
  /// calm and prevents the "list of instructions at once" problem. <= 5 s.
  static const Duration _announcementCooldown = Duration(seconds: 5);

  /// Minimum forward movement before a "continue straight" update is allowed.
  static const double _minMovementForUpdate = 6.0;

  /// How long the periodic re-check ticks. Each tick still respects the
  /// global cooldown, so this only governs *when we evaluate*, not how often
  /// we speak.
  static const Duration _tickInterval = Duration(seconds: 3);

  /// Heading delta (degrees) beyond which an orientation correction fires.
  static const double _alignmentDeadzoneDeg = kStraightThresholdDeg;

  /// Heading delta (degrees) below which orientation is considered "aligned"
  /// again (hysteresis lower bound, prevents flapping around the deadzone).
  static const double _alignmentClearDeg = 25.0;

  /// How far ahead along the route to aim the "desired heading" target. A few
  /// meters smooths the target across maneuver vertices so left/right
  /// corrections don't flip-flop.
  static const double _lookAheadMeters = 8.0;

  /// Speed (m/s) above which the user is considered "walking": GPS course is
  /// then trusted as the facing direction and orientation nagging is paused.
  static const double _movingSpeed = 0.6;

  /// Don't issue the opposite orientation correction within this window unless
  /// the user is badly misaligned (anti-oscillation).
  static const Duration _alignFlipGuard = Duration(seconds: 6);

  // --- Dependencies ---------------------------------------------------------

  final GetRouteUseCase _getRoute;
  final CompassService _compass;
  final void Function(String) _onInstruction;

  // --- State ----------------------------------------------------------------

  RouteEntity? _currentRoute;
  Location? _currentDestination;
  int _currentStepIndex = 0;

  /// Index of the polyline segment the user is currently on, from projecting
  /// the live GPS position onto the route. Drives robust step progression.
  int _currentSegmentIndex = 0;
  bool _isNavigating = false;
  bool _isReady = false;
  bool _isRerouting = false;

  StreamSubscription<Position>? _locationSub;
  StreamSubscription<double?>? _compassSub;
  Timer? _readyTimer;
  Timer? _tickTimer;

  Position? _currentPosition;
  double? _gpsHeading;
  final HeadingFilter _headingFilter = HeadingFilter();

  DateTime _lastEmitAt = DateTime.fromMillisecondsSinceEpoch(0);
  String _lastEmitText = '';
  Position? _lastProgressPosition;
  int _consecutiveOffRouteFixes = 0;

  /// Direction of the last orientation correction (-1 left, +1 right, 0 none)
  /// and when it was issued — used to damp left/right oscillation.
  int _lastAlignDir = 0;
  DateTime _lastAlignAt = DateTime.fromMillisecondsSinceEpoch(0);

  final StreamController<NavigationSnapshot> _snapshotController =
      StreamController<NavigationSnapshot>.broadcast();
  NavigationSnapshot _snapshot = NavigationSnapshot.idle;

  NavigationService({
    required GetRouteUseCase getRoute,
    required CompassService compass,
    required void Function(String) onInstruction,
  }) : _getRoute = getRoute,
       _compass = compass,
       _onInstruction = onInstruction;

  // --- Public API -----------------------------------------------------------

  bool get isNavigating => _isNavigating;
  bool get hasRoute => _currentRoute != null;

  /// Live snapshot stream consumed by the map UI.
  Stream<NavigationSnapshot> get snapshots => _snapshotController.stream;
  NavigationSnapshot get currentSnapshot => _snapshot;

  /// Best available heading (degrees). While walking, the GPS course over
  /// ground is the most reliable indicator of facing and needs no magnetic
  /// calibration; when stopped, fall back to the smoothed compass.
  double? get _stableHeading {
    final pos = _currentPosition;
    if (pos != null && pos.speed > _movingSpeed && pos.heading >= 0) {
      return pos.heading;
    }
    final compass = _headingFilter.smoothedHeading;
    if (compass != null && _headingFilter.isStable) return compass;
    return _gpsHeading;
  }

  Future<String> buildRoute(Location destination) async {
    final position = await _getCurrentLocation();

    final route = await _getRoute(
      sourceLat: position.latitude,
      sourceLng: position.longitude,
      destLat: destination.latitude,
      destLng: destination.longitude,
    );

    if (_isNavigating) {
      _stopSensors();
      _readyTimer?.cancel();
      _tickTimer?.cancel();
    }

    final cleanedInstructions = route.instructions.map((step) {
      return step.Edit(instruction: _normalizeInstruction(step.instruction));
    }).toList();

    _currentRoute = route.Edit(instructions: cleanedInstructions);
    _currentDestination = destination;
    _currentStepIndex = 0;
    _currentSegmentIndex = 0;
    _isNavigating = false;
    _isReady = false;
    _consecutiveOffRouteFixes = 0;
    _lastProgressPosition = null;
    _currentPosition = position;

    _publishSnapshot();

    final totalMeters = _routeTotalDistance().toInt();
    return 'Route to ${destination.name} is ready. '
        'Total walking distance is about $totalMeters meters. '
        'Say start navigation to begin.';
  }

  String startNavigation() {
    if (_currentRoute == null) {
      return 'Please specify a destination first by saying navigate to.';
    }
    if (_isNavigating) {
      return 'Navigation is already in progress.';
    }

    _isNavigating = true;
    _isReady = false;
    _currentStepIndex = 0;
    _currentSegmentIndex = 0;
    _consecutiveOffRouteFixes = 0;
    _lastEmitAt = DateTime.fromMillisecondsSinceEpoch(0);
    _lastEmitText = '';
    _lastProgressPosition = null;
    _lastAlignDir = 0;
    _headingFilter.reset();

    _startSensors();
    _readyTimer?.cancel();
    _readyTimer = Timer(_readyDelay, _onReady);
    _startTickTimer();
    _publishSnapshot();

    return 'Navigation started. I will guide you as you walk '
        'and announce each turn when you reach it.';
  }

  String stopNavigation() {
    final wasNavigating = _isNavigating;
    _isNavigating = false;
    _isReady = false;
    _isRerouting = false;
    _stopSensors();
    _readyTimer?.cancel();
    _readyTimer = null;
    _tickTimer?.cancel();
    _tickTimer = null;
    _currentRoute = null;
    _currentDestination = null;
    _currentStepIndex = 0;
    _currentSegmentIndex = 0;
    _consecutiveOffRouteFixes = 0;
    _lastProgressPosition = null;
    _lastAlignDir = 0;
    _snapshot = NavigationSnapshot.idle;
    _publishSnapshot();

    return wasNavigating ? 'Navigation stopped.' : 'Navigation is not active.';
  }

  void dispose() {
    _stopSensors();
    _readyTimer?.cancel();
    _tickTimer?.cancel();
    _snapshotController.close();
  }

  String _normalizeInstruction(String text) {
    final lower = text.toLowerCase();

    return lower
        .replaceAll('bear left', 'follow the road curving left')
        .replaceAll('bear right', 'follow the road curving right')
        .replaceAll('slight left', 'slight left')
        .replaceAll('slight right', 'slight right')
        .replaceAll('turn left', 'turn left')
        .replaceAll('turn right', 'turn right')
        .replaceAll('continue', 'continue straight');
  }
  // --- Sensors --------------------------------------------------------------

  void _startSensors() {
    _locationSub?.cancel();
    _locationSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 2,
      ),
    ).listen(_onLocationUpdate);

    _compassSub?.cancel();
    _compassSub = _compass.headingStream.listen((h) {
      _headingFilter.addSample(h);
    });
    _headingFilter.addSample(_compass.currentHeading);
  }

  void _stopSensors() {
    _locationSub?.cancel();
    _locationSub = null;
    _compassSub?.cancel();
    _compassSub = null;
    _headingFilter.reset();
    _gpsHeading = null;
  }

  void _onReady() {
    _isReady = true;
    _giveFirstGuidance();
  }

  // --- Guidance: first instruction ------------------------------------------

  void _giveFirstGuidance() {
    if (!_isNavigating || _currentRoute == null) return;

    if (_currentPosition == null) {
      // _emit('Waiting for GPS signal. Please wait a few seconds.', urgent: true);
      _emit('Waiting for GPS signal. Please wait a few seconds.',
          critical: true);
      return;
    }

    final steps = _currentRoute!.instructions;
    if (steps.length < 2) {
      _emit('You are already at your destination.', critical: true);
      stopNavigation();
      return;
    }

    final next = steps[1];
    final dist = _haversineToPoint(_currentPosition!, next.lat, next.lng);

    final heading = _stableHeading;
    final desired = _desiredHeading();
    if (heading == null || desired == null) {
      _emit(
        'Begin walking forward. About ${dist.toInt()} meters to the first '
        'turn. I will correct your direction once I detect which way you '
        'are facing.',
        critical: true,
      );
      return;
    }

    // Align the user with the direction the route heads next (a look-ahead
    // point), not the straight-line bearing to the maneuver node.
    final delta = angleDelta(heading, desired);
    final phrase = initialDirectionPhrase(delta);
    if (phrase.startsWith('Turn')) {
      // Needs to reorient before walking — an orientation instruction, no
      // distance attached.
      _emit('$phrase.', critical: true);
    } else {
      // Already facing the right way — a "continue" instruction, with distance.
      _emit('$phrase for ${dist.toInt()} meters.', critical: true);
    }
  }

  // --- Guidance: location-driven --------------------------------------------

  void _onLocationUpdate(Position position) {
    _currentPosition = position;

    if (position.heading >= 0 && position.speed > 0.5) {
      _gpsHeading = position.heading;
    }

    _publishSnapshot();

    if (!_isNavigating || _currentRoute == null || !_isReady || _isRerouting) {
      return;
    }

    if (_isOffRoute(position)) {
      _consecutiveOffRouteFixes++;
      if (_consecutiveOffRouteFixes >= _offRouteFixesRequired) {
        _consecutiveOffRouteFixes = 0;
        _reroute(position);
      }
      return;
    } else {
      _consecutiveOffRouteFixes = 0;
    }

    final steps = _currentRoute!.instructions;
    final coords = _currentRoute!.coordinates;

    // Track where we are along the route by projecting onto the polyline.
    final projection = projectOntoPolyline(
      position.latitude,
      position.longitude,
      coords,
    );
    if (projection != null) {
      // Only ever move forward along the route.
      if (projection.segmentIndex > _currentSegmentIndex) {
        _currentSegmentIndex = projection.segmentIndex;
      }
    }

    // Global arrival check: announce arrival whenever we are within the
    // arrival radius of the destination, even if step progression stalled.
    final destDist = _distanceToDestination();
    if (destDist != null && destDist < _arrivalThreshold) {
      _emit('You have arrived at your destination.', critical: true);
      stopNavigation();
      return;
    }

    // On the final step there is no further maneuver; the periodic update
    // handles "continue to your destination".
    if (_currentStepIndex >= steps.length - 1) {
      return;
    }

    final next = steps[_currentStepIndex + 1];
    final maneuverVertex = next.polylineIndex;

    // Straight-line distance to the maneuver point. This decreases
    // monotonically as the user approaches, unlike the segment-sum which could
    // grow if polyline-segment tracking stalled.
    final distToNext = _haversineToPoint(position, next.lat, next.lng);

    // Has the user passed the maneuver vertex? Backup so a missed trigger
    // never strands the engine on the wrong step.
    final passedManeuver =
        maneuverVertex >= 0 && _currentSegmentIndex >= maneuverVertex;

    if (distToNext <= _maneuverTriggerDistance || passedManeuver) {
      final phrase = _maneuverPhrase(next);
      if (isTurnInstruction(phrase)) {
        _emit('${capitalizeFirst(phrase)}.', critical: true);
      }
      _currentStepIndex++;
      _lastProgressPosition = position;
      return;
    }
  }

  // --- Guidance: periodic re-check (alignment + progress) -------------------

  void _startTickTimer() {
    _tickTimer?.cancel();
    _tickTimer = Timer.periodic(_tickInterval, (_) => _tick());
  }

  void _tick() {
    if (!_isNavigating ||
        !_isReady ||
        _currentPosition == null ||
        _currentRoute == null ||
        _isRerouting) {
      return;
    }

    // Respect the global cooldown: never evaluate a new spoken update if we
    // spoke very recently.
    if (DateTime.now().difference(_lastEmitAt) < _announcementCooldown) {
      return;
    }

    // 1) Orientation correction — path-relative and double-checked.
    final correction = _checkAlignment();
    if (correction != null) {
      _emit('${capitalizeFirst(correction)}.');
      return;
    }

    // 2) Progress update only after the user has actually moved.
    if (_lastProgressPosition != null) {
      final moved = Geolocator.distanceBetween(
        _lastProgressPosition!.latitude,
        _lastProgressPosition!.longitude,
        _currentPosition!.latitude,
        _currentPosition!.longitude,
      );
      if (moved < _minMovementForUpdate) return;
    }
    _lastProgressPosition = _currentPosition;

    final steps = _currentRoute!.instructions;
    if (_currentStepIndex >= steps.length - 1) {
      final destDist = _distanceToDestination();
      if (destDist == null) return;
      _emit('Continue straight ahead for ${destDist.toInt()} meters '
          'to your destination.');
      return;
    }

    final next = steps[_currentStepIndex + 1];
    final dist = _haversineToPoint(_currentPosition!, next.lat, next.lng);
    _emit('Continue straight ahead for ${dist.toInt()} meters.');
  }

  /// Returns an alignment correction phrase, or null when on-course.
  ///
  /// Only corrects orientation when the user is essentially STATIONARY — while
  /// walking, forward motion is its own confirmation, and nagging there caused
  /// the false "turn to face the path" reports. The target is a look-ahead
  /// point along the route (stable across maneuver vertices), and a small
  /// hysteresis prevents rapid left/right flapping.
  String? _checkAlignment() {
    final pos = _currentPosition;
    if (pos == null || _currentRoute == null) return null;

    if (pos.speed > _movingSpeed) {
      _lastAlignDir = 0;
      return null;
    }

    final heading = _stableHeading;
    if (heading == null) return null;
    if (!_headingFilter.isStable && _gpsHeading == null) return null;

    final desired = _desiredHeading();
    if (desired == null) return null;

    final delta = angleDelta(heading, desired);
    final absD = delta.abs();

    // Aligned again -> clear hysteresis, no correction.
    if (absD < _alignmentClearDeg) {
      _lastAlignDir = 0;
      return null;
    }
    if (absD < _alignmentDeadzoneDeg) return null;

    final dir = delta > 0 ? 1 : -1;
    final now = DateTime.now();
    // Suppress an immediate opposite correction (anti-oscillation) unless the
    // user is badly misaligned (> 90 degrees).
    if (_lastAlignDir != 0 &&
        dir != _lastAlignDir &&
        now.difference(_lastAlignAt) < _alignFlipGuard &&
        absD < 90) {
      return null;
    }
    _lastAlignDir = dir;
    _lastAlignAt = now;
    return describeAlignmentCorrection(delta);
  }

  /// Desired heading: the bearing from the user toward a point a few meters
  /// ahead along the route. Stable across maneuver vertices, so corrections
  /// don't flip left/right at corners.
  double? _desiredHeading() {
    final pos = _currentPosition;
    final route = _currentRoute;
    if (pos == null || route == null) return null;
    final coords = route.coordinates;
    if (coords.length < 2) return null;
    final proj = projectOntoPolyline(pos.latitude, pos.longitude, coords);
    if (proj == null) return null;
    final ahead = pointAheadOnPolyline(
      coords,
      proj.segmentIndex,
      proj.snappedLat,
      proj.snappedLng,
      _lookAheadMeters,
    );
    if (ahead == null) return null;
    return bearingBetween(pos.latitude, pos.longitude, ahead[0], ahead[1]);
  }

  String _maneuverPhrase(TurnByTurnStep next) {
    final heading = _stableHeading;
    if (heading != null && next.bearingAfter != null) {
      final delta = angleDelta(heading, next.bearingAfter!);
      return describeTurn(delta);
    }
    return modifierToPhrase(next.modifier, fallbackType: next.maneuverType);
  }

  // --- Geometry helpers -----------------------------------------------------

  double _haversineToPoint(Position position, double lat, double lng) {
    return Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      lat,
      lng,
    );
  }

  double? _distanceToDestination() {
    if (_currentPosition == null || _currentDestination == null) return null;
    return Geolocator.distanceBetween(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
      _currentDestination!.latitude,
      _currentDestination!.longitude,
    );
  }

  double _routeTotalDistance() {
    if (_currentRoute == null) return 0;
    double total = 0;
    for (final step in _currentRoute!.instructions) {
      total += step.distance;
    }
    return total;
  }

  bool _isOffRoute(Position position) {
    if (_currentRoute == null || _currentRoute!.coordinates.isEmpty) {
      return false;
    }
    final dist = distancePointToPolylineMeters(
      position.latitude,
      position.longitude,
      _currentRoute!.coordinates,
    );
    return dist > _offRouteThreshold;
  }

  Future<void> _reroute(Position position) async {
    if (_currentDestination == null || _isRerouting) return;
    _isRerouting = true;

    _emit('You are off the route. Recalculating.', critical: true);

    try {
      final newRoute = await _getRoute(
        sourceLat: position.latitude,
        sourceLng: position.longitude,
        destLat: _currentDestination!.latitude,
        destLng: _currentDestination!.longitude,
      );
      _currentRoute = newRoute;
      _currentStepIndex = 0;
      _currentSegmentIndex = 0;
      _lastProgressPosition = null;
      _publishSnapshot();

      Timer(const Duration(seconds: 1), _giveFirstGuidance);
    } catch (_) {
      _emit('Failed to recalculate route. Please try again.', critical: true);
    } finally {
      _isRerouting = false;
    }
  }

  Future<Position> _getCurrentLocation() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();

    if (!serviceEnabled) {
      await Geolocator.openLocationSettings();
      throw Exception('Location services disabled');
    }

    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.deniedForever) {
      await Geolocator.openAppSettings();
      throw Exception('Permission permanently denied');
    }

    if (permission == LocationPermission.denied) {
      throw Exception('Location permission is required');
    }

    return Geolocator.getCurrentPosition();
  }

  // --- Emission with a single global cooldown -------------------------------

  /// Emits a spoken instruction.
  ///
  /// [critical] events (turn now, arrival, off-route, GPS wait) bypass the
  /// cooldown because they are time-sensitive and never conflict with one
  /// another. All routine guidance is gated by [_announcementCooldown] so the
  /// engine cannot stack instructions while the user is standing still.
  void _emit(String text, {bool critical = false}) {
    final now = DateTime.now();

    // if (_isSpeaking && !urgent) return;
    // if (!urgent && now.difference(_lastEmitAt) < _minBetweenAnnouncements) {
    if (!critical && now.difference(_lastEmitAt) < _announcementCooldown) {
      return;
    }
    // Never repeat the exact same line back-to-back.
    if (text == _lastEmitText &&
        now.difference(_lastEmitAt) < const Duration(seconds: 6)) {
      return;
    }

    _lastEmitAt = now;
    _lastEmitText = text;
    _snapshot = _snapshot.copyWith(lastInstruction: text);
    _publishSnapshot();
    _onInstruction(text);
  }

  void _publishSnapshot() {
    _snapshot = _snapshot.copyWith(
      isNavigating: _isNavigating,
      route: _currentRoute,
      userLat: _currentPosition?.latitude,
      userLng: _currentPosition?.longitude,
      heading: _stableHeading,
      destinationLat: _currentDestination?.latitude,
      destinationLng: _currentDestination?.longitude,
      destinationName: _currentDestination?.name,
      distanceToDestination: _distanceToDestination(),
    );
    if (!_snapshotController.isClosed) {
      _snapshotController.add(_snapshot);
    }
  }
}
