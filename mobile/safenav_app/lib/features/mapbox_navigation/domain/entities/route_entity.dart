import './turn_by_turn_step.dart';

class RouteEntity {
  final List<List<double>> coordinates;
  final List<TurnByTurnStep> instructions;

  RouteEntity({required this.coordinates, required this.instructions});

  RouteEntity Edit({
    List<List<double>>? coordinates,
    List<TurnByTurnStep>? instructions,
  }) {
    return RouteEntity(
      instructions: instructions ?? this.instructions,
      coordinates: coordinates ?? this.coordinates,
    );
  }
}
