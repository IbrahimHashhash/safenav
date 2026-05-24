import '../../domain/entities/location.dart';
import '../../domain/entities/voice_command.dart';

class IntentParserService {
  static const List<String> _navigateTriggers = [
    'navigate',
    'go',
    'take',
    'direct',
    'directions',
    'get',
    'head',
    'bring',
    'lead',
    'show',
  ];

  static const List<String> _fillerWords = [
    'to',
    'me',
    'can',
    'you',
    'please',
    'i',
    'want',
    'need',
    'would',
    'like',
    'could',
    'the',
    'a',
    'an',
  ];

  static const List<String> _moreInfoTriggers = [
    'info',
    'help',
    'commands',
  ];

  static const List<String> _repeatTriggers = [
    'repeat',
    'again',
  ];

  VoiceCommand parse(String text) {
    final normalized = _normalize(text);

    if (normalized.isEmpty) {
      return VoiceCommand(type: VoiceCommandType.unknown);
    }

    final words = normalized.split(' ');

    // More specific intents first
    if (_containsIntent(words, _moreInfoTriggers)) {
      return VoiceCommand(type: VoiceCommandType.moreInfo);
    }

    if (_containsIntent(words, _repeatTriggers)) {
      return VoiceCommand(type: VoiceCommandType.repeat);
    }

    // Explicit navigation intent
    if (_containsIntent(words, _navigateTriggers)) {
      final location = _extractLocation(words);

      if (location != null) {
        return VoiceCommand(
          type: VoiceCommandType.navigate,
          argument: location.name,
        );
      }
    }

    // Direct destination speech
    // Example: "library"
    final directLocation = _findBestLocation(normalized);

    if (directLocation != null) {
      return VoiceCommand(
        type: VoiceCommandType.navigate,
        argument: directLocation.name,
      );
    }

    return VoiceCommand(type: VoiceCommandType.unknown);
  }

  String _normalize(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  bool _containsIntent(List<String> words, List<String> triggers) {
    for (final word in words) {
      for (final trigger in triggers) {
        if (_isSimilar(word, trigger, threshold: 0.3)) {
          return true;
        }
      }
    }

    return false;
  }

  Location? _extractLocation(List<String> words) {
    final filteredWords = words.where((word) {
      return !_isIgnoredWord(word) && word.length > 1;
    }).toList();

    if (filteredWords.isEmpty) {
      return null;
    }

    final candidate = filteredWords.join(' ');

    return _findBestLocation(candidate);
  }

  bool _isIgnoredWord(String word) {
    return _matchesAny(word, _navigateTriggers) ||
        _matchesAny(word, _fillerWords);
  }

  bool _matchesAny(String word, List<String> list) {
    for (final item in list) {
      if (_isSimilar(word, item, threshold: 0.3)) {
        return true;
      }
    }

    return false;
  }

  Location? _findBestLocation(String candidate) {
    Location? bestMatch;
    double bestScore = 0;

    final candidateWords = candidate.split(' ').toSet();

    for (final location in Location.all) {
      final locationName = _normalize(location.name);

      // Exact contains shortcut
      if (locationName.contains(candidate) ||
          candidate.contains(locationName)) {
        return location;
      }

      final locationWords = locationName.split(' ').toSet();

      // Token overlap score
      final intersection =
          candidateWords.intersection(locationWords).length;

      final union = candidateWords.union(locationWords).length;

      final tokenScore = union == 0 ? 0 : intersection / union;

      // Levenshtein similarity
      final editScore = 1 -
          (_levenshtein(candidate, locationName) /
              _max(candidate.length, locationName.length));

      // Combined score
      final finalScore = (tokenScore * 0.6) + (editScore * 0.4);

      if (finalScore > bestScore) {
        bestScore = finalScore;
        bestMatch = location;
      }
    }

    // Confidence threshold
    return bestScore >= 0.55 ? bestMatch : null;
  }

  bool _isSimilar(
    String a,
    String b, {
    double threshold = 0.25,
  }) {
    final distance = _levenshtein(a, b);
    final similarity = distance / _max(a.length, b.length);

    return similarity <= threshold;
  }

  int _max(int a, int b) => a > b ? a : b;

  int _levenshtein(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;

    final dp = List.generate(
      a.length + 1,
      (i) => List.filled(b.length + 1, 0),
    );

    for (int i = 0; i <= a.length; i++) {
      dp[i][0] = i;
    }

    for (int j = 0; j <= b.length; j++) {
      dp[0][j] = j;
    }

    for (int i = 1; i <= a.length; i++) {
      for (int j = 1; j <= b.length; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;

        dp[i][j] = [
          dp[i - 1][j] + 1,
          dp[i][j - 1] + 1,
          dp[i - 1][j - 1] + cost,
        ].reduce((x, y) => x < y ? x : y);
      }
    }

    return dp[a.length][b.length];
  }
}