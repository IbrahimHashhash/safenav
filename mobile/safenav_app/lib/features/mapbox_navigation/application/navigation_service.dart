import 'dart:async';
import 'package:geolocator/geolocator.dart';
import '../../mapbox_navigation/domain/entities/route_entity.dart';
import '../../mapbox_navigation/domain/usecases/get_route_usecase.dart';
import '../../../shared/models/location.dart';

class NavigationService {
  final GetRouteUseCase _getRoute;
  final Function(String) _onInstruction;

  RouteEntity? _currentRoute;
  int _currentStepIndex = 0;
  bool _isNavigating = false;
  StreamSubscription<Position>? _locationSubscription;

  static const double _proximityThreshold = 30.0; // meters

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

    _currentStepIndex = 0;
    _isNavigating = false;

    return 'Route to ${destination.name} is ready. Say start navigation to begin';
  }

  String startNavigation() {
    if (_currentRoute == null) {
      return 'Please specify a destination first by saying navigate to';
    }

    _isNavigating = true;
    _startLocationTracking();
    return _getCurrentInstruction() ?? 'Navigation started';
  }

  void _startLocationTracking() {
    _locationSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5, // Update every 5 meters
      ),
    ).listen(_onLocationUpdate);
  }

  void _onLocationUpdate(Position position) {
    if (!_isNavigating || _currentRoute == null) return;

    final instructions = _currentRoute!.instructions;
    if (_currentStepIndex >= instructions.length) {
      _onInstruction('You have arrived at your destination');
      stopNavigation();
      return;
    }

    final currentStep = instructions[_currentStepIndex];
    final distance = Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      currentStep.lat,
      currentStep.lng,
    );

    // When user is close to the waypoint, announce next instruction
    if (distance <= _proximityThreshold) {
      _currentStepIndex++;
      
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

  String? _getCurrentInstruction() {
    if (_currentRoute == null) return null;
    final instructions = _currentRoute!.instructions;
    if (_currentStepIndex >= instructions.length) return null;
    
    final step = instructions[_currentStepIndex];
    return '${step.instruction}. Distance: ${step.distance.toInt()} meters';
  }

  String stopNavigation() {
    _isNavigating = false;
    _locationSubscription?.cancel();
    _locationSubscription = null;
    _currentRoute = null;
    _currentStepIndex = 0;
    return 'Navigation stopped';
  }

  Future<Position> _getCurrentLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw Exception('Location services are disabled');
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw Exception('Location permissions are denied');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      throw Exception('Location permissions are permanently denied');
    }

    return await Geolocator.getCurrentPosition();
  }

  void dispose() {
    _locationSubscription?.cancel();
  }
}
