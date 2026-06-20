import 'dart:async';

import 'package:geolocator/geolocator.dart';

import '../../../core/services/compass/compass_service.dart';
import '../../../shared/models/location.dart';
import '../domain/engine/geo_point.dart';
import '../domain/engine/heading_filter.dart';
import '../domain/engine/nav_engine.dart';
import '../domain/engine/route_path.dart';
import '../domain/entities/navigation_snapshot.dart';
import '../domain/entities/route_entity.dart';
import '../domain/usecases/get_route_usecase.dart';

/// Pedestrian turn-by-turn navigation engine.
///
/// The post-processing (route model, turn classification, distances,
/// orientation, speech vocabulary, cooldown/dedup) is the pure-Dart engine
/// under `domain/engine` (ported from the Google-nav reference so the two apps
/// behave identically). This service is the platform boundary: it builds a
/// [RoutePath] from the Mapbox route, feeds GPS + compass events into the
/// [NavEngine] and [HeadingFilter], speaks whatever the engine emits, and
/// publishes a [NavigationSnapshot] for the map UI.
class NavigationService {
  static const double _offRouteThreshold = 25.0;
  static const int _offRouteFixesRequired = 3;

  /// Throttle compass-driven re-evaluations (speech is further gated by the
  /// engine's own cooldown). Lets orientation corrections fire while the user
  /// is stationary and only rotating.
  static const Duration _compassEvalInterval = Duration(milliseconds: 300);

  final GetRouteUseCase _getRoute;
  final CompassService _compass;
  final void Function(String) _onInstruction;

  // Route + engine.
  RouteEntity? _currentRoute; // kept for the map polyline / snapshot
  RoutePath? _routePath;
  NavEngine? _engine;
  Location? _currentDestination;

  bool _isNavigating = false;
  bool _isRerouting = false;
  int _consecutiveOffRouteFixes = 0;

  // Sensors.
  StreamSubscription<Position>? _locationSub;
  StreamSubscription<double?>? _compassSub;
  Position? _currentPosition;

  final HeadingFilter _headingFilter = HeadingFilter();
  HeadingEstimate _heading = HeadingEstimate.empty;
  DateTime _lastCompassEval = DateTime.fromMillisecondsSinceEpoch(0);

  // Snapshot.
  double? _distanceToDestination;
  String? _lastInstruction;
  final StreamController<NavigationSnapshot> _snapshotController =
      StreamController<NavigationSnapshot>.broadcast();
  NavigationSnapshot _snapshot = NavigationSnapshot.idle;

  NavigationService({
    required GetRouteUseCase getRoute,
    required CompassService compass,
    required void Function(String) onInstruction,
  })  : _getRoute = getRoute,
        _compass = compass,
        _onInstruction = onInstruction;

  // --- Public API -----------------------------------------------------------

  bool get isNavigating => _isNavigating;
  bool get hasRoute => _currentRoute != null;

  Stream<NavigationSnapshot> get snapshots => _snapshotController.stream;
  NavigationSnapshot get currentSnapshot => _snapshot;

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
    }

    _currentRoute = route;
    _routePath = _buildRoutePath(route);
    _engine = null;
    _currentDestination = destination;
    _isNavigating = false;
    _isRerouting = false;
    _consecutiveOffRouteFixes = 0;
    _currentPosition = position;
    _distanceToDestination = _routePath?.totalLength;
    _lastInstruction = null;
    _publishSnapshot();

    final totalMeters = (_routePath?.totalLength ?? 0).round();
    return 'Route to ${destination.name} is ready. '
        'Total walking distance is about $totalMeters meters. '
        'Say start navigation to begin.';
  }

  String startNavigation() {
    if (_currentRoute == null || _routePath == null) {
      return 'Please specify a destination first by saying navigate to.';
    }
    if (_isNavigating) {
      return 'Navigation is already in progress.';
    }
    if (_routePath!.vertices.length < 2) {
      return 'You are already at your destination.';
    }

    _isNavigating = true;
    _isRerouting = false;
    _consecutiveOffRouteFixes = 0;
    _lastInstruction = null;
    _headingFilter.reset();
    _heading = HeadingEstimate.empty;
    _engine = NavEngine(_routePath!);

    _startSensors();
    _publishSnapshot();

    return 'Navigation started. I will guide you as you walk '
        'and announce each turn when you reach it.';
  }

  String stopNavigation() {
    final wasNavigating = _isNavigating;
    _isNavigating = false;
    _isRerouting = false;
    _stopSensors();
    _engine = null;
    _routePath = null;
    _currentRoute = null;
    _currentDestination = null;
    _consecutiveOffRouteFixes = 0;
    _distanceToDestination = null;
    _snapshot = NavigationSnapshot.idle;
    _publishSnapshot();

    return wasNavigating ? 'Navigation stopped.' : 'Navigation is not active.';
  }

  void dispose() {
    _stopSensors();
    _snapshotController.close();
  }

  // --- Sensors --------------------------------------------------------------

  void _startSensors() {
    _locationSub?.cancel();
    _locationSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 2,
      ),
    ).listen(_onLocationUpdate);

    _compassSub?.cancel();
    _compassSub = _compass.headingStream.listen(_onCompass);
    final cached = _compass.currentHeading;
    if (cached != null) _heading = _headingFilter.add(cached);
  }

  void _stopSensors() {
    _locationSub?.cancel();
    _locationSub = null;
    _compassSub?.cancel();
    _compassSub = null;
    _headingFilter.reset();
    _heading = HeadingEstimate.empty;
  }

  void _onLocationUpdate(Position position) {
    _currentPosition = position;
    if (!_isNavigating || _engine == null || _isRerouting) {
      _publishSnapshot();
      return;
    }
    _evaluate(GeoPoint(position.latitude, position.longitude), DateTime.now());
  }

  void _onCompass(double? raw) {
    if (raw == null) return;
    _heading = _headingFilter.add(raw);

    final now = DateTime.now();
    if (_isNavigating &&
        _engine != null &&
        _currentPosition != null &&
        !_isRerouting &&
        now.difference(_lastCompassEval) >= _compassEvalInterval) {
      _lastCompassEval = now;
      _evaluate(
        GeoPoint(_currentPosition!.latitude, _currentPosition!.longitude),
        now,
      );
    } else {
      _publishSnapshot();
    }
  }

  // --- Core evaluation ------------------------------------------------------

  void _evaluate(GeoPoint geo, DateTime now) {
    final engine = _engine;
    final path = _routePath;
    if (engine == null || path == null) return;

    // Off-route detection (cross-track from the route polyline).
    final proj = path.project(geo);
    if (proj.crossTrackDistance > _offRouteThreshold) {
      _consecutiveOffRouteFixes++;
      if (_consecutiveOffRouteFixes >= _offRouteFixesRequired && !_isRerouting) {
        _consecutiveOffRouteFixes = 0;
        _reroute();
      }
      return;
    }
    _consecutiveOffRouteFixes = 0;

    final update = engine.update(
      position: geo,
      heading: _heading.smoothedHeading,
      headingStable: _heading.isStable,
      now: now,
    );

    final remaining = path.totalLength - update.projection.distanceAlong;
    _distanceToDestination = remaining < 0 ? 0 : remaining;

    final inst = update.instruction;
    if (inst != null) {
      _speak(inst.text);
    }

    if (update.arrived) {
      stopNavigation();
      return;
    }
    _publishSnapshot();
  }

  Future<void> _reroute() async {
    final dest = _currentDestination;
    final pos = _currentPosition;
    if (dest == null || pos == null || _isRerouting) return;
    _isRerouting = true;
    _speak('You are off the route. Recalculating.');

    try {
      final newRoute = await _getRoute(
        sourceLat: pos.latitude,
        sourceLng: pos.longitude,
        destLat: dest.latitude,
        destLng: dest.longitude,
      );
      _currentRoute = newRoute;
      _routePath = _buildRoutePath(newRoute);
      _engine = _routePath == null ? null : NavEngine(_routePath!);
      _consecutiveOffRouteFixes = 0;
      _publishSnapshot();
    } catch (_) {
      _speak('Failed to recalculate route. Please try again.');
    } finally {
      _isRerouting = false;
    }
  }

  // --- Helpers --------------------------------------------------------------

  RoutePath? _buildRoutePath(RouteEntity route) {
    final coords = route.coordinates;
    if (coords.length < 2) return null;
    final polyline = <GeoPoint>[
      for (final c in coords)
        if (c.length >= 2) GeoPoint(c[0], c[1]),
    ];
    if (polyline.length < 2) return null;
    final nodes = <GeoPoint>[
      for (final s in route.instructions) GeoPoint(s.lat, s.lng),
    ];
    return RoutePath.build(polyline: polyline, maneuverNodes: nodes);
  }

  /// Forwards an instruction to TTS + the snapshot. The engine already applies
  /// cooldown and de-duplication, so this does not re-gate.
  void _speak(String text) {
    _lastInstruction = text;
    _publishSnapshot();
    _onInstruction(text);
  }

  void _publishSnapshot() {
    _snapshot = NavigationSnapshot(
      isNavigating: _isNavigating,
      route: _currentRoute,
      userLat: _currentPosition?.latitude,
      userLng: _currentPosition?.longitude,
      heading: _heading.smoothedHeading,
      destinationLat: _currentDestination?.latitude,
      destinationLng: _currentDestination?.longitude,
      destinationName: _currentDestination?.name,
      distanceToDestination: _distanceToDestination,
      lastInstruction: _lastInstruction,
    );
    if (!_snapshotController.isClosed) {
      _snapshotController.add(_snapshot);
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
}
