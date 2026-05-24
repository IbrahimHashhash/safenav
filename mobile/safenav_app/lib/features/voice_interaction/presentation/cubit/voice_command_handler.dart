
import '../../../../core/constants/help_info_messages.dart';
import 'package:safenav_app/shared/models/location.dart';
import '../../domain/entities/voice_command.dart';
import '../../domain/services/intent_parser_service.dart';
import '../../domain/services/location_extractor_service.dart';
import 'speech_queue.dart';

class VoiceCommandHandler {
  final IntentParserService intentParser;
  final LocationExtractorService locationExtractor;

  const VoiceCommandHandler({
    required this.intentParser,
    required this.locationExtractor,
  });

  SpeechRequest handle(String text) {
    final intent = intentParser.detect(text);

    if (intent == VoiceCommandType.navigate) {
      final location = locationExtractor.extract(text);
      return location != null
          ? SpeechRequest('Navigating to ${location.name}', SpeechPriority.assistant)
          : const SpeechRequest('Sorry, I couldn\'t find that location', SpeechPriority.assistant);
    }

    if (intent == VoiceCommandType.listLocations) {
      final category = locationExtractor.extractCategory(text);
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