import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../domain/entities/navigation_snapshot.dart';
import '../cubit/navigation_map_cubit.dart';
import 'orientation_arrow.dart';









class NavigationMapView extends StatefulWidget {
  const NavigationMapView({
    super.key,
    this.mapboxToken = '',
    this.mapboxStyle = 'mapbox/streets-v12',
    this.showCoordinates = false,
  });

  final String mapboxToken;
  final String mapboxStyle;

  
  final bool showCoordinates;

  @override
  State<NavigationMapView> createState() => _NavigationMapViewState();
}

class _NavigationMapViewState extends State<NavigationMapView> {
  final MapController _mapController = MapController();
  bool _autoFollow = true;
  bool _mapReady = false;

  StreamSubscription<Position>? _posSub;
  LatLng? _gpsLatLng;
  double? _gpsHeading;
  LatLng? _lastFollowed;

  static const LatLng _campusCenter = LatLng(31.9601, 35.1824);

  bool get _useMapbox => widget.mapboxToken.isNotEmpty;

  String get _tileUrl => _useMapbox
      ? 'https://api.mapbox.com/styles/v1/{styleId}/tiles/256/{z}/{x}/{y}@2x'
          '?access_token={accessToken}'
      : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

  Map<String, String> get _tileTemplateValues => _useMapbox
      ? {'styleId': widget.mapboxStyle, 'accessToken': widget.mapboxToken}
      : const {};

  @override
  void initState() {
    super.initState();
    _startLocationStream();
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _startLocationStream() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }

      _posSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 1,
        ),
      ).listen((position) {
        if (!mounted) return;
        setState(() {
          _gpsLatLng = LatLng(position.latitude, position.longitude);
          if (position.heading >= 0 && position.speed > 0.5) {
            _gpsHeading = position.heading;
          }
        });
      });
    } catch (_) {
      
    }
  }

  
  LatLng? _resolveUser(NavigationSnapshot snapshot) {
    if (snapshot.hasUserLocation) {
      return LatLng(snapshot.userLat!, snapshot.userLng!);
    }
    return _gpsLatLng;
  }

  double? _resolveHeading(NavigationSnapshot snapshot) =>
      snapshot.heading ?? _gpsHeading;

  void _follow(LatLng? target) {
    if (!_autoFollow || !_mapReady || target == null) return;
    if (_lastFollowed == target) return;
    _lastFollowed = target;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final zoom =
          _mapController.camera.zoom < 16 ? 18.0 : _mapController.camera.zoom;
      _mapController.move(target, zoom);
    });
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<NavigationMapCubit, NavigationSnapshot>(
      builder: (context, snapshot) {
        final user = _resolveUser(snapshot);
        final heading = _resolveHeading(snapshot);
        _follow(user);

        final routePoints = snapshot.route?.coordinates
                .map((c) => LatLng(c[0], c[1]))
                .toList() ??
            const <LatLng>[];

        return Stack(
          children: [
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: user ?? _campusCenter,
                initialZoom: 17,
                minZoom: 14,
                maxZoom: 20,
                onMapReady: () {
                  _mapReady = true;
                  _follow(user);
                },
                onPointerDown: (_, position) {
                  if (_autoFollow) setState(() => _autoFollow = false);
                },
              ),
              children: [
                TileLayer(
                  urlTemplate: _tileUrl,
                  additionalOptions: _tileTemplateValues,
                  userAgentPackageName: 'com.safenav.app',
                  maxZoom: 20,
                ),
                if (routePoints.length >= 2)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: routePoints,
                        strokeWidth: 6,
                        color: const Color(0xFF1A73E8),
                        borderStrokeWidth: 2,
                        borderColor: Colors.white,
                      ),
                    ],
                  ),
                MarkerLayer(
                  markers: [
                    if (snapshot.destinationLat != null &&
                        snapshot.destinationLng != null)
                      Marker(
                        point: LatLng(
                          snapshot.destinationLat!,
                          snapshot.destinationLng!,
                        ),
                        width: 40,
                        height: 40,
                        alignment: Alignment.topCenter,
                        child: const Icon(Icons.location_on,
                            color: Colors.red, size: 40),
                      ),
                    if (user != null)
                      Marker(
                        point: user,
                        width: 60,
                        height: 60,
                        child: OrientationArrow(headingDegrees: heading),
                      ),
                  ],
                ),
              ],
            ),
            if (snapshot.lastInstruction != null &&
                snapshot.lastInstruction!.isNotEmpty)
              _InstructionBanner(text: snapshot.lastInstruction!),
            if (widget.showCoordinates)
              _CoordinatesChip(location: user, heading: heading),
            if (!_autoFollow)
              Positioned(
                right: 16,
                bottom: 24,
                child: FloatingActionButton(
                  heroTag: 'recenter',
                  onPressed: () {
                    setState(() => _autoFollow = true);
                    _lastFollowed = null; 
                    _follow(_resolveUser(snapshot));
                  },
                  child: const Icon(Icons.my_location),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _CoordinatesChip extends StatelessWidget {
  const _CoordinatesChip({required this.location, required this.heading});

  final LatLng? location;
  final double? heading;

  @override
  Widget build(BuildContext context) {
    final text = location == null
        ? 'Waiting for GPS…'
        : 'Lat ${location!.latitude.toStringAsFixed(6)}, '
            'Lng ${location!.longitude.toStringAsFixed(6)}'
            '${heading != null ? '  •  ${heading!.toStringAsFixed(0)}°' : ''}';
    return Positioned(
      top: 8,
      left: 8,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          text,
          style: const TextStyle(color: Colors.white, fontSize: 12),
        ),
      ),
    );
  }
}

class _InstructionBanner extends StatelessWidget {
  const _InstructionBanner({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 12,
      left: 12,
      right: 12,
      child: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(12),
        color: const Color(0xFF1A73E8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              const Icon(Icons.navigation, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  text,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
