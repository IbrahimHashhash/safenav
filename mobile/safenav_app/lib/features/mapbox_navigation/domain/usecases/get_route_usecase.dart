//
import '../entities/route_entity.dart';
import '../repositories/route_repository.dart';

class GetRouteUseCase {
  final RouteRepository repository;

  GetRouteUseCase(
    this.repository,
  ); // when you create an object from this class you must give it repository

  Future<RouteEntity> call({
    required double sourceLat,
    required double sourceLng,
    required double destLat,
    required double destLng,
  }) {
    return repository.getRoute(
      sourceLat: sourceLat,
      sourceLng: sourceLng,
      destLat: destLat,
      destLng: destLng,
    );
  }
}
