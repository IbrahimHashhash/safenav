import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../domain/entities/navigation_snapshot.dart';
import '../cubit/navigation_map_cubit.dart';
import 'orientation_arrow.dart';

/// Live navigation map: OpenStreetMap tiles, the active route polyline, the
/// destination pin, and a Google-Maps-style orientation arrow that follows the
/// user. The camera recenters on the user as they move.
class NavigationMapView extends StatefulWidget {
  const NavigationMapView({super.key});

  @override
  State<NavigationMapView> createState() => _NavigationMapViewState();
}

class _NavigationMapViewState extends State<NavigationMapView> {
  final MapController _mapController = MapController();
  bool _autoFollow = true;
  bool _mapReady = false;

  static const LatLng _campusCenter = LatLng(31.9601, 35.1824);

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  void _maybeFollow(NavigationSnapshot snapshot) {
    if (!_autoFollow || !_mapReady || !snapshot.hasUserLocation) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _mapController.move(
        LatLng(snapshot.userLat!, snapshot.userLng!),
        _mapController.camera.zoom < 16 ? 18 : _mapController.camera.zoom,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<NavigationMapCubit, NavigationSnapshot>(
      listener: (context, snapshot) => _maybeFollow(snapshot),
      builder: (context, snapshot) {
        final user = snapshot.hasUserLocation
            ? LatLng(snapshot.userLat!, snapshot.userLng!)
            : null;

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
                  _maybeFollow(snapshot);
                },
                onPointerDown: (_, position) {
                  if (_autoFollow) setState(() => _autoFollow = false);
                },
              ),
              children: [
                TileLayer(
                  urlTemplate:
                      'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
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
                        child: const Icon(
                          Icons.location_on,
                          color: Colors.red,
                          size: 40,
                        ),
                      ),
                    if (user != null)
                      Marker(
                        point: user,
                        width: 60,
                        height: 60,
                        child: OrientationArrow(
                          headingDegrees: snapshot.heading,
                        ),
                      ),
                  ],
                ),
              ],
            ),
            if (snapshot.lastInstruction != null &&
                snapshot.lastInstruction!.isNotEmpty)
              _InstructionBanner(text: snapshot.lastInstruction!),
            if (!_autoFollow)
              Positioned(
                right: 16,
                bottom: 24,
                child: FloatingActionButton(
                  heroTag: 'recenter',
                  onPressed: () {
                    setState(() => _autoFollow = true);
                    _maybeFollow(snapshot);
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
