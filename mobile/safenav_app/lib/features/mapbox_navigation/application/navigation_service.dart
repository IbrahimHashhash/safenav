import 'dart:async';

import 'package:geolocator/geolocator.dart';

import '../../../core/services/compass/compass_service.dart';
import '../../../shared/models/location.dart';
import '../domain/entities/route_entity.dart';
import '../domain/entities/turn_by_turn_step.dart';
import '../domain/usecases/get_route_usecase.dart';
import 'navigation_helpers.dart';

class NavigationService {
  static const double _maneuverProximity = 8.0;
  static const double _arrivalThreshold = 10.0;
  static const double _offRouteThreshold = 25.0;
  static const int _offRouteFixesRequired = 3;
  static const Duration _readyDelay = Duration(seconds: 3);
  static const Duration _periodicInterval = Duration(seconds: 18);
  static const Duration _minBetweenAnnouncements = Duration(seconds: 3);
  static const Duration _alignmentCooldown = Duration(seconds: 8);
  static const double _periodicMinMovement = 4.0;
  static const List<int> _milestones = [100, 50, 20];

  final GetRouteUseCase _getRoute;
  final CompassService _compass;
  final void Function(String) _onInstruction;

  RouteEntity? _currentRoute;
  Location? _currentDestination;
  int _currentStepIndex = 0;
  bool _isNavigating = false;
  bool _isReady = false;
  bool _isRerouting = false;
  bool _isSpeaking = false;

  StreamSubscription<Position>? _locationSub;
  StreamSubscription<double?>? _compassSub;
  Timer? _readyTimer;
  Timer? _periodicTimer;

  Position? _currentPosition;
  double? _compassHeading;
  double? _gpsHeading;

  final Set<int> _milestonesAnnounced = <int>{};
  DateTime _lastEmitAt = DateTime.fromMillisecondsSinceEpoch(0);
  String _lastEmitText = '';
  DateTime _lastAlignmentEmitAt = DateTime.fromMillisecondsSinceEpoch(0);
  Position? _lastPeriodicPosition;
  int _consecutiveOffRouteFixes = 0;

  NavigationService({
    required GetRouteUseCase getRoute,
    required CompassService compass,
    required void Function(String) onInstruction,
  }) : _getRoute = getRoute,
       _compass = compass,
       _onInstruction = onInstruction;

  bool get isNavigating => _isNavigating;
  bool get hasRoute => _currentRoute != null;

  double? get _currentHeading => _compassHeading ?? _gpsHeading;

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
      _periodicTimer?.cancel();
    }

    final cleanedInstructions = route.instructions.map((step) {
      return step.Edit(instruction: _normalizeInstruction(step.instruction));
    }).toList();

    _currentRoute = route.Edit(instructions: cleanedInstructions);
    _currentDestination = destination;
    _currentStepIndex = 0;
    _isNavigating = false;
    _isReady = false;
    _milestonesAnnounced.clear();
    _consecutiveOffRouteFixes = 0;
    _lastPeriodicPosition = null;

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
    _milestonesAnnounced.clear();
    _consecutiveOffRouteFixes = 0;
    _lastEmitAt = DateTime.fromMillisecondsSinceEpoch(0);
    _lastAlignmentEmitAt = DateTime.fromMillisecondsSinceEpoch(0);
    _lastEmitText = '';
    _lastPeriodicPosition = null;

    _startSensors();
    _readyTimer?.cancel();
    _readyTimer = Timer(_readyDelay, _onReady);
    _startPeriodicTimer();

    return 'Navigation started. I will guide you continuously '
        'and announce upcoming turns in advance.';
  }

  String stopNavigation() {
    final wasNavigating = _isNavigating;
    _isNavigating = false;
    _isReady = false;
    _isRerouting = false;
    _stopSensors();
    _readyTimer?.cancel();
    _readyTimer = null;
    _periodicTimer?.cancel();
    _periodicTimer = null;
    _currentRoute = null;
    _currentDestination = null;
    _currentStepIndex = 0;
    _milestonesAnnounced.clear();
    _consecutiveOffRouteFixes = 0;
    _lastPeriodicPosition = null;

    return wasNavigating ? 'Navigation stopped.' : 'Navigation is not active.';
  }

  void dispose() {
    _stopSensors();
    _readyTimer?.cancel();
    _periodicTimer?.cancel();
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
      _compassHeading = h;
    });
    final cached = _compass.currentHeading;
    if (cached != null) _compassHeading = cached;
  }

  void _stopSensors() {
    _locationSub?.cancel();
    _locationSub = null;
    _compassSub?.cancel();
    _compassSub = null;
    _compassHeading = null;
    _gpsHeading = null;
  }

  void _onReady() {
    _isReady = true;
    _giveFirstGuidance();
  }

  void _giveFirstGuidance() {
    if (!_isNavigating || _currentRoute == null) return;

    if (_currentPosition == null) {
      _emit('Waiting for GPS signal. Please wait a few seconds.', urgent: true);
      return;
    }

    final steps = _currentRoute!.instructions;
    if (steps.length < 2) {
      _emit('You are already at your destination.', urgent: true);
      stopNavigation();
      return;
    }

    final next = steps[1];
    final dist = _haversineToPoint(_currentPosition!, next.lat, next.lng);

    final heading = _currentHeading;
    if (heading == null) {
      _emit(
        'Begin walking forward. About ${dist.toInt()} meters to the first '
        'turn. I will correct your direction once I detect your orientation.',
        urgent: true,
      );
      return;
    }

    final required = bearingBetween(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
      next.lat,
      next.lng,
    );
    final delta = angleDelta(heading, required);
    final phrase = initialDirectionPhrase(delta);
    _emit(
      '$phrase. About ${dist.toInt()} meters to the first turn.',
      urgent: true,
    );
  }

  void _startPeriodicTimer() {
    _periodicTimer?.cancel();
    _periodicTimer = Timer.periodic(_periodicInterval, (_) {
      _periodicGuidance();
    });
  }

  void _onLocationUpdate(Position position) {
    _currentPosition = position;

    if (position.heading >= 0 && position.speed > 0.3) {
      _gpsHeading = position.heading;
    }

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

    if (_currentStepIndex >= steps.length - 1) {
      final destDist = _distanceToDestination();
      if (destDist != null && destDist < _arrivalThreshold) {
        _emit('You have arrived at your destination.', urgent: true);
        stopNavigation();
      }
      return;
    }

    final next = steps[_currentStepIndex + 1];
    final distToNext = _haversineToPoint(position, next.lat, next.lng);

    if (distToNext < _maneuverProximity) {
      final phrase = _maneuverPhrase(next);
      _emit('$phrase now.', urgent: true);
      _currentStepIndex++;
      _milestonesAnnounced.clear();
      return;
    }

    for (final ms in _milestones) {
      if (!_milestonesAnnounced.contains(ms) && distToNext <= ms.toDouble()) {
        final phrase = _maneuverPhrase(next);
        _emit('In $ms meters, $phrase.');
        _milestonesAnnounced.add(ms);
        break;
      }
    }
  }

  void _periodicGuidance() {
    if (!_isNavigating ||
        !_isReady ||
        _currentPosition == null ||
        _currentRoute == null ||
        _isRerouting) {
      return;
    }

    if (DateTime.now().difference(_lastEmitAt) < const Duration(seconds: 6)) {
      return;
    }

    final correction = _checkAlignment();
    if (correction != null) {
      _emitAlignmentCorrection(correction);
      return;
    }

    if (_lastPeriodicPosition != null) {
      final moved = Geolocator.distanceBetween(
        _lastPeriodicPosition!.latitude,
        _lastPeriodicPosition!.longitude,
        _currentPosition!.latitude,
        _currentPosition!.longitude,
      );
      if (moved < _periodicMinMovement) return;
    }
    _lastPeriodicPosition = _currentPosition;

    final steps = _currentRoute!.instructions;
    if (_currentStepIndex >= steps.length - 1) {
      final destDist = _distanceToDestination();
      if (destDist == null) return;
      _emit('Continue straight. ${destDist.toInt()} meters to destination.');
      return;
    }

    final next = steps[_currentStepIndex + 1];
    final dist = _haversineToPoint(_currentPosition!, next.lat, next.lng);
    _emit('Continue walking. ${dist.toInt()} meters to next turn.');
  }

  String? _checkAlignment() {
    final heading = _currentHeading;
    if (heading == null || _currentPosition == null || _currentRoute == null) {
      return null;
    }
    final required = _requiredHeading();
    if (required == null) return null;
    final delta = angleDelta(heading, required);
    return describeAlignmentCorrection(delta);
  }

  void _emitAlignmentCorrection(String phrase) {
    final now = DateTime.now();
    if (now.difference(_lastAlignmentEmitAt) < _alignmentCooldown) return;
    _lastAlignmentEmitAt = now;
    _emit('${capitalizeFirst(phrase)}.', urgent: true);
  }

  String _maneuverPhrase(TurnByTurnStep next) {
    final heading = _currentHeading;
    if (heading != null && next.bearingAfter != null) {
      final delta = angleDelta(heading, next.bearingAfter!);
      return describeTurn(delta);
    }
    return modifierToPhrase(next.modifier, fallbackType: next.maneuverType);
  }

  double? _requiredHeading() {
    if (_currentPosition == null || _currentRoute == null) return null;
    final steps = _currentRoute!.instructions;

    if (_currentStepIndex >= steps.length - 1) {
      final dest = _currentDestination;
      if (dest == null) return null;
      return bearingBetween(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
        dest.latitude,
        dest.longitude,
      );
    }

    final next = steps[_currentStepIndex + 1];
    return bearingBetween(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
      next.lat,
      next.lng,
    );
  }

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

    _emit('You are off the route. Recalculating.', urgent: true);

    try {
      final newRoute = await _getRoute(
        sourceLat: position.latitude,
        sourceLng: position.longitude,
        destLat: _currentDestination!.latitude,
        destLng: _currentDestination!.longitude,
      );
      _currentRoute = newRoute;
      _currentStepIndex = 0;
      _milestonesAnnounced.clear();
      _lastPeriodicPosition = null;

      Timer(const Duration(seconds: 1), _giveFirstGuidance);
    } catch (_) {
      _emit('Failed to recalculate route. Please try again.', urgent: true);
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

  void _emit(String text, {bool urgent = false}) {
    final now = DateTime.now();

    if (_isSpeaking && !urgent) return;

    if (!urgent && now.difference(_lastEmitAt) < _minBetweenAnnouncements) {
      return;
    }
    if (text == _lastEmitText &&
        now.difference(_lastEmitAt) < const Duration(seconds: 4)) {
      return;
    }

    _lastEmitAt = now;
    _lastEmitText = text;
    _onInstruction(text);

    Future.delayed(const Duration(seconds: 2), () {
      _isSpeaking = false;
    });
  }
}
