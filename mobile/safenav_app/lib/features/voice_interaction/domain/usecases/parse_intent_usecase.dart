import '../../../../core/utils/text_utils.dart';
import '../../../../core/constants/voice_constants.dart';
import '../entities/voice_command.dart';

class ParseIntentUseCase {
  VoiceCommandType call(String text) {
    final words = TextUtils.normalize(text).split(' ');

    if (_containsIntent(words, VoiceConstants.nextInstructionTriggers)) {
      return VoiceCommandType.nextInstruction;
    }

    // Obstacle detection toggle (checked before navigation; its trigger words
    // — "detection"/"obstacle" — do not overlap the navigate triggers).
    final hasDetection =
        _containsIntent(words, VoiceConstants.detectionTriggers);
    if (hasDetection &&
        _containsIntent(words, VoiceConstants.stopNavigationTriggers)) {
      return VoiceCommandType.stopDetection;
    }
    if (hasDetection &&
        _containsIntent(words, VoiceConstants.startNavigationTriggers)) {
      return VoiceCommandType.startDetection;
    }

    if (_containsIntent(words, VoiceConstants.stopNavigationTriggers) &&
        _containsIntent(words, VoiceConstants.navigateTriggers)) {
      return VoiceCommandType.stopNavigation;
    }

    if (_containsIntent(words, VoiceConstants.startNavigationTriggers) &&
        _containsIntent(words, VoiceConstants.navigateTriggers)) {
      return VoiceCommandType.startNavigation;
    }

    if (_containsIntent(words, VoiceConstants.moreInfoTriggers)) {
      return VoiceCommandType.moreInfo;
    }

    if (_containsIntent(words, VoiceConstants.repeatTriggers)) {
      return VoiceCommandType.repeat;
    }

    if (_containsIntent(words, VoiceConstants.listTriggers)) {
      return VoiceCommandType.listLocations;
    }

    if (_containsIntent(words, VoiceConstants.navigateTriggers)) {
      return VoiceCommandType.navigate;
    }

    // Greeting is checked last (before unknown) so a phrase like
    // "hey, navigate to the library" is still treated as a navigation command.
    if (_containsIntent(words, VoiceConstants.greetingTriggers)) {
      return VoiceCommandType.greeting;
    }

    return VoiceCommandType.unknown;
  }

  bool _containsIntent(List<String> words, List<String> triggers) {
    return words.any((word) =>
        triggers.any((trigger) => TextUtils.isSimilar(word, trigger)));
  }
}
