import 'voice_command.dart';

class IntentParserService {
  VoiceCommand parse(String text) {
    final lower = text.toLowerCase();

    if (lower.startsWith('navigate to')) {
      final destination =
          lower.replaceFirst('navigate to', '').trim();

      return VoiceCommand(
        type: VoiceCommandType.navigate,
        argument: destination,
      );
    }

    if (lower.contains('more info')) {
      return VoiceCommand(
        type: VoiceCommandType.moreInfo,
      );
    }

    if (lower.contains('repeat')) {
      return VoiceCommand(
        type: VoiceCommandType.repeat,
      );
    }

    return VoiceCommand(
      type: VoiceCommandType.unknown,
    );
  }
}