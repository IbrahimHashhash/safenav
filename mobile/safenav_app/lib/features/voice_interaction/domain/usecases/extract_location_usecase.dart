import 'package:safenav_app/shared/models/location.dart';
import '../../../../core/utils/text_utils.dart';
import '../../../../core/constants/voice_constants.dart';

class ExtractLocationUseCase {
  Location? call(String text) {
    final normalized = TextUtils.normalize(text);
    final words = normalized.split(' ');

    final candidates = words
        .where((w) => !_isIgnoredWord(w) && w.length > 1)
        .join(' ');

    if (candidates.isEmpty) return null;

    return _findBestLocation(candidates);
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

    final candidateWords = candidate.split(' ').toSet();

    for (final location in Location.all) {
      final locationName = TextUtils.normalize(location.name);

      if (locationName.contains(candidate) || candidate.contains(locationName)) {
        return location;
      }

      final locationWords = locationName.split(' ').toSet();
      final intersection = candidateWords.intersection(locationWords).length;
      final union = candidateWords.union(locationWords).length;
      final tokenScore = union == 0 ? 0 : intersection / union;
      final editScore = 1 -
          (TextUtils.levenshtein(candidate, locationName) /
              (candidate.length > locationName.length
                  ? candidate.length
                  : locationName.length));

      final finalScore = (tokenScore * 0.6) + (editScore * 0.4);

      if (finalScore > bestScore) {
        bestScore = finalScore;
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
