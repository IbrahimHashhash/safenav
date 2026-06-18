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

  /// Distance (meters) at which arrival is announced.
  static const double _arrivalThreshold = 6.0;
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
  static const Duration _tickInterval = Duration(seconds: 4);

  /// Heading delta (degrees) beyond which an orientation correction fires.
  /// Matches the "still straight" threshold so a user on the correct path is
  /// never told to turn.
  static const double _alignmentDeadzoneDeg = kStraightThresholdDeg;

  /// Snapped-distance noise floor: ignore tiny lateral offsets from the path.
  static const double _alignmentMinOffRouteMeters = 6.0;

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

  /// Smoothed, validated heading (degrees). Null until the sensor stabilises.
  double? get _stableHeading {
    final compass = _headingFilter.smoothedHeading;
    if (compass != null && _headingFilter.isStable) return compass;
    // Fall back to GPS course only when moving (it is meaningless when still).
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

    final coords = _currentRoute!.coordinates;
    final projection = projectOntoPolyline(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
      coords,
    );

    final next = steps[1];
    final dist = _haversineToPoint(_currentPosition!, next.lat, next.lng);

    final heading = _stableHeading;
    if (heading == null || projection == null) {
      _emit(
        'Begin walking forward. About ${dist.toInt()} meters to the first '
        'turn. I will correct your direction once I detect which way you '
        'are facing.',
        critical: true,
      );
      return;
    }

    // Align the user with the direction of the route segment they are on,
    // not the straight-line bearing to the maneuver node.
    final delta = angleDelta(heading, projection.segmentBearing);
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
    // This is what makes turn detection robust: we no longer require the GPS
    // to land on the exact maneuver point.
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

    // Reached the final step: only arrival remains.
    if (_currentStepIndex >= steps.length - 1) {
      final destDist = _distanceToDestination();
      if (destDist != null && destDist < _arrivalThreshold) {
        _emit('You have arrived at your destination.', critical: true);
        stopNavigation();
      }
      return;
    }

    final next = steps[_currentStepIndex + 1];
    final maneuverVertex = next.polylineIndex;

    // Remaining distance to the maneuver measured ALONG the route polyline
    // (not straight-line), so it stays accurate around curves.
    final distToNext = maneuverVertex >= 0
        ? _distanceAlongRoute(coords, _currentSegmentIndex, maneuverVertex,
            position)
        : _haversineToPoint(position, next.lat, next.lng);

    // Has the user passed the maneuver vertex? If so, complete this step even
    // if the imperative window was somehow skipped. This prevents the engine
    // from getting stuck announcing "walk ahead" past a turn it never fired.
    final passedManeuver =
        maneuverVertex >= 0 && _currentSegmentIndex >= maneuverVertex;

    // Fire the turn when within the (reachable) trigger window OR right as we
    // cross the maneuver vertex. Either way we advance to the next step so it
    // can never re-fire or get stuck.
    //
    // Turns carry NO distance: the instruction is spoken at the moment the
    // user reaches the turn point. Slight deviations collapse to "continue
    // straight ahead" (see helpers) and are not spoken as a turn here — going
    // straight is covered by the periodic progress updates instead.
    if (distToNext <= _maneuverTriggerDistance || passedManeuver) {
      final phrase = _maneuverPhrase(next);
      if (isTurnInstruction(phrase)) {
        _emit('${capitalizeFirst(phrase)}.', critical: true);
      }
      _currentStepIndex++;
      _lastProgressPosition = position;
      return;
    }

    // for (final ms in _milestones) {
    // Pre-announcements: "in N meters, turn left." One per milestone, only
    // when actually approaching. These are framed as advance notice, NOT as
    // an instruction to turn immediately.
    // for (final ms in _approachMilestones) {
    //   if (!_milestonesAnnounced.contains(ms) && distToNext <= ms.toDouble()) {
    //     final phrase = _maneuverPhrase(next);
    //     _emit('In $ms meters, $phrase.');
    //     _milestonesAnnounced.add(ms);
    //     break;
    //   }
    // }
  }

  /// Distance in meters from the user's projected position to a target
  /// polyline vertex, summed along the route segments. Falls back gracefully
  /// when indices are out of range.
  double _distanceAlongRoute(
    List<List<double>> coords,
    int fromSegment,
    int toVertex,
    Position position,
  ) {
    if (coords.length < 2 || toVertex <= 0) {
      return _haversineToPoint(
          position, coords.isNotEmpty ? coords.last[0] : position.latitude,
          coords.isNotEmpty ? coords.last[1] : position.longitude);
    }

    // Distance from the user to the end of their current segment.
    final segEnd = (fromSegment + 1).clamp(0, coords.length - 1);
    double total = Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      coords[segEnd][0],
      coords[segEnd][1],
    );

    // Plus the length of each subsequent segment up to the maneuver vertex.
    for (int i = segEnd; i < toVertex && i < coords.length - 1; i++) {
      total += Geolocator.distanceBetween(
        coords[i][0],
        coords[i][1],
        coords[i + 1][0],
        coords[i + 1][1],
      );
    }
    return total;
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
    final coords = _currentRoute!.coordinates;
    if (_currentStepIndex >= steps.length - 1) {
      final destDist = _distanceToDestination();
      if (destDist == null) return;
      _emit('Continue straight ahead for ${destDist.toInt()} meters '
          'to your destination.');
      return;
    }

    final next = steps[_currentStepIndex + 1];
    final maneuverVertex = next.polylineIndex;
    final dist = maneuverVertex >= 0
        ? _distanceAlongRoute(
            coords, _currentSegmentIndex, maneuverVertex, _currentPosition!)
        : _haversineToPoint(_currentPosition!, next.lat, next.lng);
    _emit('Continue straight ahead for ${dist.toInt()} meters.');
  }

  /// Returns an alignment correction phrase, or null when on-course.
  ///
  /// Path-relative: compares the (stable) heading to the bearing of the route
  /// segment the user is currently on. Suppressed when the user is essentially
  /// on the line (small lateral offset) so that walking along the edge of a
  /// wide path does not trigger a spurious "turn slightly left".
  String? _checkAlignment() {
    // final heading = _currentHeading;
    final heading = _stableHeading;
    if (heading == null || _currentPosition == null || _currentRoute == null) {
      return null;
    }
    // Require a *stable* compass reading before trusting a correction.
    if (!_headingFilter.isStable && _gpsHeading == null) return null;

    final coords = _currentRoute!.coordinates;
    final projection = projectOntoPolyline(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
      coords,
    );
    if (projection == null) return null;

    // If the user is basically on the path, do not nag about orientation.
    if (projection.distanceMeters < _alignmentMinOffRouteMeters) {
      final delta = angleDelta(heading, projection.segmentBearing);
      if (delta.abs() < _alignmentDeadzoneDeg) return null;
    }

    final delta = angleDelta(heading, projection.segmentBearing);
    if (delta.abs() < _alignmentDeadzoneDeg) return null;

    return describeAlignmentCorrection(delta);
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
