import '../../../core/constants/help_info_messages.dart';
import 'package:safenav_app/shared/models/location.dart';
import '../../../core/services/profile/user_profile_service.dart';
import '../../../core/utils/text_utils.dart';
import '../../mapbox_navigation/application/navigation_service.dart';
import '../../obstacle_avoidance/application/detection_controller.dart';
import '../domain/entities/voice_command.dart';
import '../domain/usecases/extract_location_usecase.dart';
import '../domain/usecases/parse_intent_usecase.dart';
import 'speech_queue.dart';



const List<String> _namePrefixes = [
  'my name is',
  'my name',
  'the name is',
  'name is',
  'you can call me',
  'call me',
  'i am',
  'im',
  'i m',
  'this is',
  'it is',
  'its',
  'it s',
];

const Set<String> _nameStopWords = {
  'hi', 'hello', 'hey', 'please', 'thanks', 'thank', 'you', 'yeah', 'yes',
};



const Set<String> _leadingFillers = {
  'hi', 'hello', 'hey', 'hiya', 'howdy', 'greetings', 'helo', 'hii',
  'yeah', 'yes', 'ok', 'okay', 'well', 'so', 'um', 'hmm', 'oh',
};



String? extractSpokenName(String text) {
  var t = TextUtils.normalize(text); 
  if (t.isEmpty) return null;

  
  var tokens = t.split(' ').where((w) => w.isNotEmpty).toList();
  while (tokens.isNotEmpty && _leadingFillers.contains(tokens.first)) {
    tokens.removeAt(0);
  }
  t = tokens.join(' ');
  if (t.isEmpty) return null;

  
  for (final prefix in _namePrefixes) {
    if (t == prefix) return null;
    if (t.startsWith('$prefix ')) {
      t = t.substring(prefix.length).trim();
      break;
    }
  }

  final words = t
      .split(' ')
      .where((w) => w.isNotEmpty && !_nameStopWords.contains(w))
      .toList();
  if (words.isEmpty) return null;

  
  return words.take(2).map(_capitalize).join(' ');
}

String _capitalize(String w) =>
    w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}';

class VoiceCommandHandler {
  final ParseIntentUseCase parseIntent;
  final ExtractLocationUseCase extractLocation;
  final NavigationService navigationService;
  final UserProfileService userProfile;

  
  
  DetectionController? detection;

  VoiceCommandHandler({
    required this.parseIntent,
    required this.extractLocation,
    required this.navigationService,
    required this.userProfile,
  });

  
  
  bool _awaitingName = false;

  static const Set<VoiceCommandType> _actionableIntents = {
    VoiceCommandType.navigate,
    VoiceCommandType.startNavigation,
    VoiceCommandType.stopNavigation,
    VoiceCommandType.startDetection,
    VoiceCommandType.stopDetection,
    VoiceCommandType.listLocations,
    VoiceCommandType.moreInfo,
    VoiceCommandType.nextInstruction,
    VoiceCommandType.repeat,
    VoiceCommandType.changeName,
  };

  Future<SpeechRequest> handle(String text) async {
    final intent = parseIntent(text);

    
    
    if (_awaitingName && !_actionableIntents.contains(intent)) {
      return _captureName(text);
    }
    _awaitingName = false;

    if (intent == VoiceCommandType.greeting) {
      return _greet();
    }

    if (intent == VoiceCommandType.changeName) {
      _awaitingName = true;
      return SpeechRequest(
        userProfile.hasName
            ? 'Okay ${userProfile.name}, what name would you like me to use '
                'instead?'
            : 'Sure, what name would you like me to use?',
        SpeechPriority.assistant,
      );
    }

    if (intent == VoiceCommandType.navigate) {
      final location = extractLocation(text);
      if (location == null) {
        final candidate = extractLocation.extractCandidate(text);
        if (candidate == null) {
          return const SpeechRequest(
            'Please specify a destination',
            SpeechPriority.assistant,
          );
        }
        return SpeechRequest(
          'Sorry, I couldn’t find "$candidate" in the map.',
          SpeechPriority.assistant,
        );
      }
      try {
        final message = await navigationService.buildRoute(location);
        return SpeechRequest(message, SpeechPriority.assistant);
      } catch (e) {
        return const SpeechRequest(
          'Unable to build route. Please check location permissions',
          SpeechPriority.assistant,
        );
      }
    }

    if (intent == VoiceCommandType.startNavigation) {
      final message = navigationService.startNavigation();
      final prefix = userProfile.hasName ? 'Okay, ${userProfile.name}. ' : '';
      return SpeechRequest('$prefix$message', SpeechPriority.assistant);
    }

    if (intent == VoiceCommandType.stopNavigation) {
      final message = navigationService.stopNavigation();
      return SpeechRequest(message, SpeechPriority.assistant);
    }

    if (intent == VoiceCommandType.startDetection) {
      return _startDetection();
    }

    if (intent == VoiceCommandType.stopDetection) {
      return _stopDetection();
    }

    if (intent == VoiceCommandType.listLocations) {
      final category = extractLocation.extractCategory(text);
      return SpeechRequest(
          _buildLocationsList(category), SpeechPriority.assistant);
    }

    if (intent == VoiceCommandType.moreInfo) {
      return const SpeechRequest(
          HelpInfoMessages.availableCommands, SpeechPriority.assistant);
    }

    final sorry = userProfile.hasName
        ? 'Sorry ${userProfile.name}, I didn\'t understand that'
        : 'Sorry, I didn\'t understand that';
    return SpeechRequest(sorry, SpeechPriority.assistant);
  }

  Future<SpeechRequest> _startDetection() async {
    final controller = detection;
    if (controller == null) {
      return const SpeechRequest(
        'Obstacle detection is not available.',
        SpeechPriority.assistant,
      );
    }
    if (controller.isDetecting) {
      return const SpeechRequest(
        'Obstacle detection is already on.',
        SpeechPriority.assistant,
      );
    }
    final started = await controller.startDetection();
    return SpeechRequest(
      started
          ? 'Obstacle detection started.'
          : 'Could not start obstacle detection. '
              'Check the camera and your internet connection.',
      SpeechPriority.assistant,
    );
  }

  Future<SpeechRequest> _stopDetection() async {
    final controller = detection;
    if (controller == null || !controller.isDetecting) {
      return const SpeechRequest(
        'Obstacle detection is not on.',
        SpeechPriority.assistant,
      );
    }
    await controller.stopDetection();
    return const SpeechRequest(
      'Obstacle detection stopped.',
      SpeechPriority.assistant,
    );
  }

  SpeechRequest _greet() {
    if (userProfile.hasName) {
      return SpeechRequest(
        'Hello, ${userProfile.name}! How can I help you today?',
        SpeechPriority.assistant,
      );
    }
    _awaitingName = true;
    return const SpeechRequest(
      "Hello! I'm your SafeNav assistant. What's your name?",
      SpeechPriority.assistant,
    );
  }

  Future<SpeechRequest> _captureName(String text) async {
    final name = extractSpokenName(text);
    if (name == null) {
      return const SpeechRequest(
        "Sorry, I didn't catch your name. Could you say it again?",
        SpeechPriority.assistant,
      );
    }
    _awaitingName = false;
    await userProfile.setName(name);
    return SpeechRequest(
      'Nice to meet you, $name! How can I help you today?',
      SpeechPriority.assistant,
    );
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
