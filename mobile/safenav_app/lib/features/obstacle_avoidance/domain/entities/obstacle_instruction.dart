/// A single obstacle-avoidance instruction extracted from the detection
/// server's response. The server returns a rich JSON object with many fields;
/// the client only cares about the human-readable `instruction` string that is
/// spoken to the user.
class ObstacleInstruction {
  final String message;

  const ObstacleInstruction({required this.message});

  /// Builds an instruction from a server response, reading ONLY the
  /// `instruction` field. Missing/null/non-string values yield an empty
  /// message (callers should skip empty instructions).
  factory ObstacleInstruction.fromJson(Map<String, dynamic> json) {
    final value = json['instruction'];
    return ObstacleInstruction(
      message: value is String ? value.trim() : '',
    );
  }

  bool get isEmpty => message.isEmpty;

  @override
  String toString() => 'ObstacleInstruction(message: $message)';
}
