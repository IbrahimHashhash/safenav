class TurnByTurnStep {
  final String instruction;
  final double distance;
  final double duration;
  final String maneuverType;
  final String? modifier;
  final double? bearingBefore;
  final double? bearingAfter;
  final double lat;
  final double lng;

  TurnByTurnStep({
    required this.instruction,
    required this.distance,
    required this.duration,
    required this.maneuverType,
    this.modifier,
    this.bearingBefore,
    this.bearingAfter,
    required this.lat,
    required this.lng,
  });

  factory TurnByTurnStep.fromJson(Map<String, dynamic> json) {
    final maneuver = json['maneuver'] as Map<String, dynamic>?;
    final location = maneuver?['location'];

    double? toDouble(dynamic v) =>
        v == null ? null : (v as num).toDouble();

    final hasLocation = location is List && location.length >= 2;

    return TurnByTurnStep(
      instruction: (maneuver?['instruction'] as String?) ?? '',
      distance: ((json['distance'] as num?) ?? 0).toDouble(),
      duration: ((json['duration'] as num?) ?? 0).toDouble(),
      maneuverType: (maneuver?['type'] as String?) ?? '',
      modifier: maneuver?['modifier'] as String?,
      bearingBefore: toDouble(maneuver?['bearing_before']),
      bearingAfter: toDouble(maneuver?['bearing_after']),
      lat: hasLocation ? (location[1] as num).toDouble() : 0.0,
      lng: hasLocation ? (location[0] as num).toDouble() : 0.0,
    );
  }
}
