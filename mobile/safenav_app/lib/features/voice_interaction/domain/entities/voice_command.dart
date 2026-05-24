import 'location.dart';

enum VoiceCommandType {
  navigate,
  repeat,
  moreInfo,
  listLocations,
  unknown,
  unknownLocation,
}

class VoiceCommand {
  final VoiceCommandType type;
  final String? argument;
  final LocationCategory? category;

  const VoiceCommand({
    required this.type,
    this.argument,
    this.category,
  });
}