class TurnByTurnStep {
  final String instruction;
  final double distance;
  final double duration;
  final String maneuverType;
  final double lat;
  final double lng;

  TurnByTurnStep({
    required this.instruction,
    required this.distance,
    required this.duration,
    required this.maneuverType,
    required this.lat,
    required this.lng,
  });

  factory TurnByTurnStep.fromJson(Map<String, dynamic> json) {
    final location = json["maneuver"]["location"];

    return TurnByTurnStep(
      instruction: json["maneuver"]?["instruction"] ?? "",
      distance: (json["distance"] ?? 0).toDouble(),
      duration: (json["duration"] ?? 0).toDouble(),
      maneuverType: json["maneuver"]?["type"] ?? "",
      lat: location != null ? location[1].toDouble() : 0,
      lng: location != 0 ? location[0].toDouble() : 0,
    );
  }
}
