import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/voice_command.dart';
import '../../domain/services/intent_parser_service.dart';
import '../../domain/services/location_extractor_service.dart';
import '../../../../core/constants/help_info_messages.dart';
import '../../../help_info/domain/entities/location.dart';

import '../../../../core/services/speech_to_text/flutter_stt_service.dart';
import '../../../../core/services/speech_to_text/stt_service.dart';
import '../../../../core/services/text_to_speech/tts_service.dart';
import 'voice_assistant_state.dart';

class VoiceAssistantCubit extends Cubit<VoiceAssistantState> {
  final SttService sttService;
  final TtsService ttsService;
  final IntentParserService intentParser;
  final LocationExtractorService locationExtractor;

  VoiceAssistantCubit({
    required this.sttService,
    required this.ttsService,
    required this.intentParser,
    required this.locationExtractor,
  }) : super(VoiceIdle());

  String _lastInstruction = '';
  bool _isPressActive = false;
  bool _hasHandledCommand = false;

  Future<void> initialize() async {
    await sttService.initialize();
  }

  Future<void> startListening() async {
    if (_isPressActive || sttService.isListening) return;

    _isPressActive = true;
    _hasHandledCommand = false;

    emit(VoiceListening());

    await sttService.startListening(
      onResult: (text, isFinal) {},
      onTimeout: _onSttTimeout,
      onError: _onSttError,
    );
  }

  void _onSttTimeout() {
    if (!_isPressActive || _hasHandledCommand) return;
    _isPressActive = false;
    emit(VoiceIdle());
  }

  void _onSttError(String message) {
    if (!_isPressActive) return;
    _isPressActive = false;
    emit(VoiceError(message));
  }

  Future<void> stopSpeaking() async {
    await ttsService.stop();
    emit(VoiceIdle());
  }

  Future<void> stopListening() async {
    if (!_isPressActive) return;

    _isPressActive = false;
    await sttService.stopListening();

    if (_hasHandledCommand) return;

    final text = (sttService as FlutterSttService).lastText;
    print('[Cubit] processing on release: "$text"');

    if (text.isNotEmpty) {
      _hasHandledCommand = true;
      await _handleRecognizedText(text);
    } else {
      emit(VoiceIdle());
    }
  }

  Future<void> _handleRecognizedText(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      emit(VoiceIdle());
      return;
    }

    final intent = intentParser.detect(trimmed);

    if (intent == VoiceCommandType.navigate) {
      final location = locationExtractor.extract(trimmed);
      await _handleCommand(VoiceCommand(
        type: location != null
            ? VoiceCommandType.navigate
            : VoiceCommandType.unknownLocation,
        argument: location?.name,
      ));
    } else if (intent == VoiceCommandType.listLocations) {
      final category = locationExtractor.extractCategory(trimmed);
      await _handleCommand(VoiceCommand(
        type: VoiceCommandType.listLocations,
        category: category,
      ));
    } else {
      await _handleCommand(VoiceCommand(type: intent));
    }
  }

  Future<void> _handleCommand(VoiceCommand command) async {
    switch (command.type) {
      case VoiceCommandType.navigate:
        final destination = command.argument ?? '';
        final text = 'Navigating to $destination';
        _lastInstruction = text;
        emit(VoiceSpeaking(text));
        ttsService.speak(text, onComplete: () => emit(VoiceIdle()));
        break;

      case VoiceCommandType.listLocations:
        final text = _buildLocationsList(command.category);
        _lastInstruction = text;
        emit(VoiceSpeaking(text));
        ttsService.speak(text, onComplete: () => emit(VoiceIdle()));
        break;

      case VoiceCommandType.moreInfo:
        final text = HelpInfoMessages.availableCommands;
        _lastInstruction = text;
        emit(VoiceSpeaking(text));
        ttsService.speak(text, onComplete: () => emit(VoiceIdle()));
        break;

      case VoiceCommandType.repeat:
        emit(VoiceSpeaking(_lastInstruction));
        ttsService.speak(_lastInstruction, onComplete: () => emit(VoiceIdle()));
        break;

      case VoiceCommandType.unknownLocation:
        const text = 'Sorry, I couldn\'t find that location';
        emit(VoiceSpeaking(text));
        ttsService.speak(text, onComplete: () => emit(VoiceIdle()));
        break;

      case VoiceCommandType.unknown:
        const text = 'Sorry, I didn\'t understand that';
        emit(VoiceSpeaking(text));
        ttsService.speak(text, onComplete: () => emit(VoiceIdle()));
        break;
    }
  }

  String _buildLocationsList(LocationCategory? category) {
    if (category != null) {
      final locations = Location.all
          .where((l) => l.category == category)
          .map((l) => l.name)
          .toList();
      final categoryName = '${category.name}s';
      return 'There are ${locations.length} $categoryName: ${locations.join(', ')}';
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