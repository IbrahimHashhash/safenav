import '../../../core/constants/help_info_messages.dart';
import 'package:safenav_app/shared/models/location.dart';
import '../domain/entities/voice_command.dart';
import '../domain/usecases/extract_location_usecase.dart';
import '../domain/usecases/parse_intent_usecase.dart';
import 'speech_queue.dart';

class VoiceCommandHandler {
  final ParseIntentUseCase parseIntent;
  final ExtractLocationUseCase extractLocation;

  const VoiceCommandHandler({
    required this.parseIntent,
    required this.extractLocation,
  });

  SpeechRequest handle(String text) {
    final intent = parseIntent(text);

    if (intent == VoiceCommandType.navigate) {
      final location = extractLocation(text);
      if (location != null) {
        return SpeechRequest(
          'Got it. your route to "${location.name} is ready".',
          SpeechPriority.assistant,
        );
      }

      final candidate = extractLocation.extractCandidate(text);
      if (candidate == null) {
        return const SpeechRequest(
          'You didn’t specify a location.',
          SpeechPriority.assistant,
        );
      }

      return SpeechRequest(
        'Sorry, I couldn’t find "$candidate" in the map.',
        SpeechPriority.assistant,
      );
    }
    if (intent == VoiceCommandType.listLocations) {
      final category = extractLocation.extractCategory(text);
      return SpeechRequest(_buildLocationsList(category), SpeechPriority.assistant);
    }

    if (intent == VoiceCommandType.moreInfo) {
      return const SpeechRequest(HelpInfoMessages.availableCommands, SpeechPriority.assistant);
    }

    return const SpeechRequest('Sorry, I didn\'t understand that', SpeechPriority.assistant);
  }

  String _buildLocationsList(LocationCategory? category) {
    if (category != null) {
      final locations = Location.all
          .where((l) => l.category == category)
          .map((l) => l.name)
          .toList();
      return 'There are ${locations.length} ${category.name}s: ${locations.join(', ')}';
    }

    final faculties = Location.all
        .where((l) => l.category == LocationCategory.faculty)
        .map((l) => l.name)
        .toList();
    final libraries = Location.all
        .where((l) => l.category == LocationCategory.library)
        .map((l) => l.name)
        .toList();
    final cafeterias = Location.all
        .where((l) => l.category == LocationCategory.cafeteria)
        .map((l) => l.name)
        .toList();

    return 'There are ${faculties.length} faculties: ${faculties.join(', ')}. '
        '${libraries.length} libraries: ${libraries.join(', ')}. '
        '${cafeterias.length} cafeterias: ${cafeterias.join(', ')}.';
  }
}
