class ObstacleInstruction {
  final String message;

  const ObstacleInstruction({required this.message});

  factory ObstacleInstruction.fromJson(Map<String, dynamic> json) {
    return ObstacleInstruction(message: json['res'] as String);
  }

  @override
  String toString() => 'ObstacleInstruction(message: $message)';
}