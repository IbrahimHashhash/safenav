import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../mapbox_navigation/domain/entities/route_entity.dart';
import '../../mapbox_navigation/domain/entities/turn_by_turn_step.dart';
import '../../mapbox_navigation/domain/repositories/route_repository.dart';

/// Alternative route provider that fetches WALKING directions from the Google
/// Directions API and returns the SAME [RouteEntity] the Mapbox provider does.
///
/// This lives in its own feature folder and does not touch the Mapbox code:
/// the navigation post-processing engine is shared, so swapping providers only
/// swaps where the route geometry + maneuver points come from.
class GoogleRouteRepository implements RouteRepository {
  GoogleRouteRepository({required this.apiKey, http.Client? client})
      : _client = client ?? http.Client();

  final String apiKey;
  final http.Client _client;

  static const String _baseUrl =
      'https://maps.googleapis.com/maps/api/directions/json';

  @override
  Future<RouteEntity> getRoute({
    required double sourceLat,
    required double sourceLng,
    required double destLat,
    required double destLng,
  }) async {
    if (apiKey.isEmpty) {
      throw Exception('Missing GOOGLE_MAPS_API_KEY');
    }

    final uri = Uri.parse(_baseUrl).replace(queryParameters: {
      'origin': '$sourceLat,$sourceLng',
      'destination': '$destLat,$destLng',
      'mode': 'walking',
      'language': 'en',
      'units': 'metric',
      'key': apiKey,
    });

    final response = await _client.get(uri);
    if (response.statusCode != 200) {
      throw Exception('Google Directions HTTP ${response.statusCode}');
    }

    final data = json.decode(response.body) as Map<String, dynamic>;
    final status = data['status'] as String? ?? 'UNKNOWN';
    if (status != 'OK') {
      throw Exception('Google Directions error: $status');
    }

    final routes = data['routes'] as List? ?? const [];
    if (routes.isEmpty) {
      throw Exception('No routes returned from Google Directions');
    }

    final route = routes.first as Map<String, dynamic>;
    final legs = route['legs'] as List? ?? const [];
    if (legs.isEmpty) {
      throw Exception('No legs in Google Directions route');
    }
    final steps = (legs.first as Map<String, dynamic>)['steps'] as List? ??
        const [];

    // Concatenate the per-step polylines for precise geometry, and use each
    // step's end_location as a candidate maneuver node (the engine anchors it
    // to the nearest vertex and keeps only geometrically significant turns).
    final coordinates = <List<double>>[];
    final instructions = <TurnByTurnStep>[];

    for (final raw in steps) {
      final step = raw as Map<String, dynamic>;

      final encoded = (step['polyline']?['points'] as String?) ?? '';
      for (final p in _decodePolyline(encoded)) {
        coordinates.add(p);
      }

      final end = step['end_location'] as Map<String, dynamic>?;
      final endLat = (end?['lat'] as num?)?.toDouble();
      final endLng = (end?['lng'] as num?)?.toDouble();
      if (endLat == null || endLng == null) continue;

      instructions.add(
        TurnByTurnStep(
          instruction: _stripHtml(step['html_instructions'] as String? ?? ''),
          distance: ((step['distance']?['value'] as num?) ?? 0).toDouble(),
          duration: ((step['duration']?['value'] as num?) ?? 0).toDouble(),
          maneuverType: (step['maneuver'] as String?) ?? '',
          lat: endLat,
          lng: endLng,
        ),
      );
    }

    if (coordinates.length < 2) {
      throw Exception('Google route geometry too short');
    }

    return RouteEntity(coordinates: coordinates, instructions: instructions);
  }

  /// Decodes a Google encoded polyline into a list of [lat, lng] pairs.
  static List<List<double>> _decodePolyline(String encoded) {
    final points = <List<double>>[];
    int index = 0;
    int lat = 0;
    int lng = 0;

    while (index < encoded.length) {
      int shift = 0;
      int result = 0;
      int b;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      lat += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      lng += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);

      points.add([lat / 1e5, lng / 1e5]);
    }
    return points;
  }

  static String _stripHtml(String html) => html
      .replaceAll(RegExp(r'<[^>]*>'), ' ')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
