import '../../domain/entities/route_entity.dart';
import '../../domain/repositories/route_repository.dart';
import '../data_sources/mapbox_datasource.dart';
import '../../domain/entities/turn_by_turn_step.dart';

class CampusRouteRepositoryImpl implements RouteRepository {
  final MapboxDataSource dataSource;

  CampusRouteRepositoryImpl(this.dataSource);

  @override
  Future<RouteEntity> getRoute({
    required double sourceLat,
    required double sourceLng,
    required double destLat,
    required double destLng,
  }) async {
    final data = await dataSource.getRoute(
      sourceLat: sourceLat,
      sourceLng: sourceLng,
      destLat: destLat,
      destLng: destLng,
    );

    final List routes = data["routes"] ?? [];

    if (routes.isEmpty) {
      throw Exception("No routes returned from Mapbox API: $data");
    }

    final bestRoute = routes.first;
    
    final geometry = bestRoute["geometry"];
    final coords = (geometry["coordinates"] as List)
      .map<List<double>>((c) => [c[1], c[0]])
        .toList();

    final legs = bestRoute["legs"] as List?;
    final rawSteps = legs != null && legs.isNotEmpty
        ? (legs[0]["steps"] as List? ?? [])
        : [];

    final steps = rawSteps
        .map((e) => TurnByTurnStep.fromJson(e))
        .toList();

    return RouteEntity(coordinates: coords, instructions: steps);
  }
}
