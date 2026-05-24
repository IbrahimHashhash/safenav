
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/voice_command.dart';
import '../../domain/services/intent_parser_service.dart';
import '../../domain/services/location_extractor_service.dart';
import '../../../../core/services/speech_to_text/flutter_stt_service.dart';
import '../../../../core/services/speech_to_text/stt_service.dart';
import '../../../../core/services/text_to_speech/tts_service.dart';
import '../cubit/speech_queue.dart';
import '../cubit/voice_command_handler.dart';
import 'voice_assistant_state.dart';

class VoiceAssistantCubit extends Cubit<VoiceAssistantState> {
  final SttService sttService;
  final TtsService ttsService;
  final IntentParserService intentParser;
  final LocationExtractorService locationExtractor;

  late final SpeechQueue _speechQueue;
  late final VoiceCommandHandler _commandHandler;

  VoiceAssistantCubit({
    required this.sttService,
    required this.ttsService,
    required this.intentParser,
    required this.locationExtractor,
  }) : super(VoiceIdle()) {
    _speechQueue = SpeechQueue(
      ttsService: ttsService,
      onSpeaking: (text) => emit(VoiceSpeaking(text)),
      onIdle: () => emit(VoiceIdle()),
    );
    _commandHandler = VoiceCommandHandler(
      intentParser: intentParser,
      locationExtractor: locationExtractor,
    );
  }

  String _lastInstruction = '';
  bool _isPressActive = false;
  bool _hasHandledCommand = false;

  Future<void> initialize() async {
    await sttService.initialize();
  }

  
  
  

  Future<void> speakObstacleInstruction(String text) async {
    if (text.trim().isEmpty) return;

    if (_isPressActive) {
      _isPressActive = false;
      _hasHandledCommand = true;
      await sttService.stopListening();
    }

    await _speechQueue.enqueue(SpeechRequest(text, SpeechPriority.obstacle));
  }

  
  
  

  Future<void> speakNavigationInstruction(String text) async {
    if (text.trim().isEmpty) return;
    await _speechQueue.enqueue(SpeechRequest(text, SpeechPriority.navigation));
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

  Future<void> stopListening() async {
    if (!_isPressActive) return;

    _isPressActive = false;
    await sttService.stopListening();

    if (_hasHandledCommand) return;

    final text = (sttService as FlutterSttService).lastText;

    if (text.isNotEmpty) {
      _hasHandledCommand = true;
      await _handleRecognizedText(text);
    } else {
      emit(VoiceIdle());
    }
  }

  Future<void> stopSpeaking() async {
    await _speechQueue.stopAll();
  }

  
  
  

  Future<void> _handleRecognizedText(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      emit(VoiceIdle());
      return;
    }

    
    if (intentParser.detect(trimmed) == VoiceCommandType.repeat) {
      if (_lastInstruction.isNotEmpty) {
        await _speechQueue.enqueue(
          SpeechRequest(_lastInstruction, SpeechPriority.assistant),
        );
      } else {
        emit(VoiceIdle());
      }
      return;
    }

    final request = _commandHandler.handle(trimmed);
    if (request.text.isEmpty) {
      emit(VoiceIdle());
      return;
    }

    _lastInstruction = request.text;
    await _speechQueue.enqueue(request);
  }
}