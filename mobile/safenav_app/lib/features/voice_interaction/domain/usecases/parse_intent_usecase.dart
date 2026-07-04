import '../../../../core/utils/text_utils.dart';
import '../../../../core/constants/voice_constants.dart';
import '../entities/voice_command.dart';

class ParseIntentUseCase {
  
  
  
  
  static const double _fuzzyThreshold = 0.66;
  static const double _fuzzyMargin = 0.08;

  
  
  
  static const Map<VoiceCommandType, List<String>> _phrases = {
    VoiceCommandType.startDetection: [
      'start detection',
      'start obstacle detection',
      'begin detection',
      'enable obstacle detection',
      'turn on detection',
    ],
    VoiceCommandType.stopDetection: [
      'stop detection',
      'stop obstacle detection',
      'end detection',
      'disable obstacle detection',
      'turn off detection',
    ],
    VoiceCommandType.startNavigation: [
      'start navigation',
      'begin navigation',
      'start navigating',
    ],
    VoiceCommandType.stopNavigation: [
      'stop navigation',
      'cancel navigation',
      'end navigation',
    ],
    VoiceCommandType.listLocations: [
      'list locations',
      'list places',
      'available locations',
      'show locations',
    ],
    VoiceCommandType.moreInfo: [
      'more info',
      'more information',
      'available commands',
      'what can you do',
    ],
    VoiceCommandType.repeat: [
      'repeat that',
      'say that again',
    ],
    VoiceCommandType.nextInstruction: [
      'next instruction',
      'continue',
    ],
    VoiceCommandType.changeName: [
      'change my name',
      'change name',
      'rename me',
      'update my name',
    ],
  };

  VoiceCommandType call(String text) {
    final normalized = TextUtils.normalize(text);
    final words = normalized.split(' ');

    if (_containsIntent(words, VoiceConstants.nextInstructionTriggers)) {
      return VoiceCommandType.nextInstruction;
    }

    
    
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

    
    
    final saysRename =
        words.any((w) => TextUtils.isSimilarWord(w, 'rename'));
    if (saysRename ||
        (_containsIntent(words, VoiceConstants.changeNameTriggers) &&
            _containsIntent(words, VoiceConstants.nameWordTriggers))) {
      return VoiceCommandType.changeName;
    }

    if (_containsIntent(words, VoiceConstants.navigateTriggers)) {
      return VoiceCommandType.navigate;
    }

    
    
    if (_containsIntent(words, VoiceConstants.greetingTriggers)) {
      return VoiceCommandType.greeting;
    }

    
    
    final fuzzy = _bestPhraseMatch(normalized);
    if (fuzzy != null) return fuzzy;

    return VoiceCommandType.unknown;
  }

  bool _containsIntent(List<String> words, List<String> triggers) {
    return words.any((word) =>
        triggers.any((trigger) => TextUtils.isSimilarWord(word, trigger)));
  }

  
  
  
  VoiceCommandType? _bestPhraseMatch(String normalized) {
    if (normalized.isEmpty) return null;

    VoiceCommandType? best;
    double bestScore = 0;
    double secondScore = 0;

    _phrases.forEach((type, phrases) {
      double typeScore = 0;
      for (final phrase in phrases) {
        final s = TextUtils.phraseSimilarity(normalized, phrase);
        if (s > typeScore) typeScore = s;
      }
      if (typeScore > bestScore) {
        secondScore = bestScore;
        bestScore = typeScore;
        best = type;
      } else if (typeScore > secondScore) {
        secondScore = typeScore;
      }
    });

    if (bestScore >= _fuzzyThreshold &&
        (bestScore - secondScore) >= _fuzzyMargin) {
      return best;
    }
    return null;
  }
}
