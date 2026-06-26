import '../../../../core/utils/text_utils.dart';
import '../../../../core/constants/voice_constants.dart';
import '../entities/voice_command.dart';

class ParseIntentUseCase {
  /// The fuzzy fallback only claims a command when the best canonical-phrase
  /// score reaches this, AND beats the runner-up by [_fuzzyMargin]. Otherwise
  /// the input is treated as unknown — for a navigation aid it's safer to ask
  /// the user to repeat than to fire the wrong command on ambiguous speech.
  static const double _fuzzyThreshold = 0.66;
  static const double _fuzzyMargin = 0.08;

  /// Canonical phrasings for the fixed (non-parameterised) commands. Used only
  /// as a fallback when precise trigger matching finds nothing, to rescue
  /// slight mishearings (e.g. "stop detension" -> stop detection).
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
  };

  VoiceCommandType call(String text) {
    final normalized = TextUtils.normalize(text);
    final words = normalized.split(' ');

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

    // Greeting is checked late (before the fuzzy fallback) so a phrase like
    // "hey, navigate to the library" is still treated as a navigation command.
    if (_containsIntent(words, VoiceConstants.greetingTriggers)) {
      return VoiceCommandType.greeting;
    }

    // Nothing matched precisely. Try a confident fuzzy match for fixed commands
    // that were slightly misheard. Ambiguous/low-confidence input stays unknown.
    final fuzzy = _bestPhraseMatch(normalized);
    if (fuzzy != null) return fuzzy;

    return VoiceCommandType.unknown;
  }

  bool _containsIntent(List<String> words, List<String> triggers) {
    return words.any((word) =>
        triggers.any((trigger) => TextUtils.isSimilarWord(word, trigger)));
  }

  /// Returns the closest fixed command only if the match is both strong
  /// ([_fuzzyThreshold]) and clearly ahead of the next-best command
  /// ([_fuzzyMargin]); otherwise null (ambiguous → unknown).
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
