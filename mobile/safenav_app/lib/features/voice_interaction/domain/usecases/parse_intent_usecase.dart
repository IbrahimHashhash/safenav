import '../../../../core/utils/text_utils.dart';
import '../../../../core/constants/voice_constants.dart';
import '../entities/voice_command.dart';

class ParseIntentUseCase {
  VoiceCommandType call(String text) {
    final words = TextUtils.normalize(text).split(' ');

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

    return VoiceCommandType.unknown;
  }

  bool _containsIntent(List<String> words, List<String> triggers) {
    return words.any((word) =>
        triggers.any((trigger) => TextUtils.isSimilar(word, trigger)));
  }
}
