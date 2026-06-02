import 'dart:async';
import 'package:geolocator/geolocator.dart';
import '../../mapbox_navigation/domain/entities/route_entity.dart';
import '../../mapbox_navigation/domain/usecases/get_route_usecase.dart';
import '../../../shared/models/location.dart';

class NavigationService {
  final GetRouteUseCase _getRoute;
  final Function(String) _onInstruction;

  RouteEntity? _currentRoute;
  Location? _currentDestination;
  int _currentStepIndex = 0;
  bool _isNavigating = false;
  bool _isReady = false;
  StreamSubscription<Position>? _locationSubscription;

  static const double _proximityThreshold = 15.0;
  static const double _rerouteThreshold = 30.0;

  NavigationService({
    required GetRouteUseCase getRoute,
    required Function(String) onInstruction,
  })  : _getRoute = getRoute,
        _onInstruction = onInstruction;

  bool get isNavigating => _isNavigating;
  bool get hasRoute => _currentRoute != null;

  Future<String> buildRoute(Location destination) async {
    final position = await _getCurrentLocation();

    _currentRoute = await _getRoute(
      sourceLat: position.latitude,
      sourceLng: position.longitude,
      destLat: destination.latitude,
      destLng: destination.longitude,
    );

    _currentDestination = destination;
    _currentStepIndex = 0;
    _isNavigating = false;
    _isReady = false;

    return 'Route to ${destination.name} is ready. Say start navigation to begin';
  }

  String startNavigation() {
    if (_currentRoute == null) {
      return 'Please specify a destination first by saying navigate to';
    }

    _isNavigating = true;
    _isReady = false;
    _startLocationTracking();
    
    Future.delayed(const Duration(seconds: 3), () {
      _isReady = true;
    });
    
    return _getCurrentInstruction() ?? 'Navigation started';
  }

  void _startLocationTracking() {
    _locationSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 3,
      ),
    ).listen(_onLocationUpdate);
  }

  void _onLocationUpdate(Position position) async {
    if (!_isNavigating || _currentRoute == null) return;

    if (_isOffRoute(position)) {
      await _reroute(position);
      return;
    }

    if (!_isReady) return;

    final instructions = _currentRoute!.instructions;
    if (_currentStepIndex >= instructions.length) {
      _onInstruction('You have arrived at your destination');
      stopNavigation();
      return;
    }

    final nextIndex = _currentStepIndex + 1;
    if (nextIndex >= instructions.length) return;

    final nextStep = instructions[nextIndex];
    final distance = Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      nextStep.lat,
      nextStep.lng,
    );

    if (distance <= _proximityThreshold) {
      _currentStepIndex = nextIndex;
      
      if (_currentStepIndex >= instructions.length) {
        _onInstruction('You have arrived at your destination');
        stopNavigation();
      } else {
        final instruction = _getCurrentInstruction();
        if (instruction != null) {
          _onInstruction(instruction);
        }
      }
    }
  }

  bool _isOffRoute(Position position) {
    if (_currentRoute == null || _currentRoute!.coordinates.isEmpty) return false;

    for (final coord in _currentRoute!.coordinates) {
      final distance = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        coord[0],
        coord[1],
      );
      if (distance < _rerouteThreshold) {
        return false;
      }
    }
    return true;
  }

  Future<void> _reroute(Position position) async {
    if (_currentDestination == null) return;

    _onInstruction('Recalculating route');

    try {
      _currentRoute = await _getRoute(
        sourceLat: position.latitude,
        sourceLng: position.longitude,
        destLat: _currentDestination!.latitude,
        destLng: _currentDestination!.longitude,
      );
      _currentStepIndex = 0;
      _isReady = false;

      Future.delayed(const Duration(seconds: 3), () {
        _isReady = true;
      });

      final instruction = _getCurrentInstruction();
      if (instruction != null) {
        _onInstruction(instruction);
      }
    } catch (e) {
      _onInstruction('Failed to recalculate route');
    }
  }

  String? _getCurrentInstruction() {
    if (_currentRoute == null) return null;
    final instructions = _currentRoute!.instructions;
    if (_currentStepIndex >= instructions.length) return null;
    
    final step = instructions[_currentStepIndex];
    return '${step.instruction}. Distance: ${step.distance.toInt()} meters';
  }

  String stopNavigation() {
    _isNavigating = false;
    _isReady = false;
    _locationSubscription?.cancel();
    _locationSubscription = null;
    _currentRoute = null;
    _currentDestination = null;
    _currentStepIndex = 0;
    return 'Navigation stopped';
  }

  Future<Position> _getCurrentLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw Exception('Please enable location services');
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw Exception('Location permission is required');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      throw Exception('Please enable location permission in settings');
    }

    return await Geolocator.getCurrentPosition();
  }

  void dispose() {
    _locationSubscription?.cancel();
  }
}
