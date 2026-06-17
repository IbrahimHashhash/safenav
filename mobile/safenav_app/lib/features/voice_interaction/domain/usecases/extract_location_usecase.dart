import 'package:safenav_app/shared/models/location.dart';
import '../../../../core/utils/text_utils.dart';
import '../../../../core/constants/voice_constants.dart';

class ExtractLocationUseCase {
  Location? call(String text) {
    final candidate = extractCandidate(text);
    if (candidate == null) return null;
    return _findBestLocation(candidate);
  }

  String? extractCandidate(String text) {
    final normalized = TextUtils.normalize(text);
    final words = normalized.split(' ');

    final candidate = words
        .where((w) => !_isIgnoredWord(w) && w.length > 1)
        .join(' ');

    if (candidate.isEmpty) return null;
    return candidate;
  }

  LocationCategory? extractCategory(String text) {
    final normalized = TextUtils.normalize(text);

    if (normalized.contains('facult')) return LocationCategory.faculty;
    if (normalized.contains('librar')) return LocationCategory.library;
    if (normalized.contains('cafeteria') || normalized.contains('cafe')) {
      return LocationCategory.cafeteria;
    }

    return null;
  }

  Location? _findBestLocation(String candidate) {
    Location? bestMatch;
    double bestScore = 0;

    for (final location in Location.all) {
      final locationName = TextUtils.normalize(location.name);
      if (locationName == candidate) return location;

      final score = TextUtils.tokenSetSimilarity(candidate, locationName);
      if (score > bestScore) {
        bestScore = score;
        bestMatch = location;
      }
    }

    return bestScore >= 0.55 ? bestMatch : null;
  }

  bool _isIgnoredWord(String word) {
    return _matchesAny(word, VoiceConstants.navigateTriggers) ||
        _matchesAny(word, VoiceConstants.fillerWords);
  }

  bool _matchesAny(String word, List<String> list) {
    return list.any((item) => TextUtils.isSimilar(word, item));
  }
}
