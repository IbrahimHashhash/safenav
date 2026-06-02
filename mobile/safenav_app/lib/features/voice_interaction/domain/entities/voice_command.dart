import 'package:safenav_app/shared/models/location.dart';

enum VoiceCommandType {
  navigate,
  repeat,
  moreInfo,
  listLocations,
  startNavigation,
  stopNavigation,
  nextInstruction,
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