import './turn_by_turn_step.dart';

class RouteEntity {
  final List<List<double>> coordinates; // [[lat, lng], ...]
  final List<TurnByTurnStep> instructions; // new field for textual directions

  RouteEntity({required this.coordinates, required this.instructions});
}
