import '../entities/route_entity.dart';

abstract class RouteRepository {
  Future<RouteEntity> getRoute({
    required double sourceLat,
    required double sourceLng,
    required double destLat,
    required double destLng,
  });
}