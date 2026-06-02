import './turn_by_turn_step.dart';

class RouteEntity {
  final List<List<double>> coordinates;
  final List<TurnByTurnStep> instructions;

  RouteEntity({required this.coordinates, required this.instructions});
}
