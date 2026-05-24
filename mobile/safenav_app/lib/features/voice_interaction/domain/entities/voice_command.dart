enum VoiceCommandType {
  navigate,
  moreInfo,
  repeat,
  unknown,
}

class VoiceCommand {
  final VoiceCommandType type;
  final String? argument;

  VoiceCommand({
    required this.type,
    this.argument,
  });
}
