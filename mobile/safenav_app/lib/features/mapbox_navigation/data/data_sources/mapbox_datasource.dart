import 'dart:convert';
import 'package:http/http.dart' as http;

class MapboxDataSource {
  final String token;

  MapboxDataSource(this.token);

  Future<Map<String, dynamic>> getRoute({
    required double sourceLat,
    required double sourceLng,
    required double destLat,
    required double destLng,
  }) async {
    final url =
        "https://api.mapbox.com/directions/v5/mapbox/walking/"
        "$sourceLng,$sourceLat;$destLng,$destLat"
        "?geometries=geojson&steps=true&overview=full"
        "&access_token=$token";

    print("MAPBOX URL: $url"); // debug

    final response = await http.get(Uri.parse(url));

    final data = jsonDecode(response.body);

    print("MAPBOX RESPONSE: $data"); // debug

    return data;
  }
}