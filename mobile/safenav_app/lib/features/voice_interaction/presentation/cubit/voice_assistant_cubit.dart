import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/voice_command.dart';
import '../../domain/services/intent_parser_service.dart';
import '../../../../core/services/speech_to_text/flutter_stt_service.dart';
import '../../../../core/services/speech_to_text/stt_service.dart';
import '../../../../core/services/text_to_speech/tts_service.dart';
import 'voice_assistant_state.dart';

class VoiceAssistantCubit extends Cubit<VoiceAssistantState> {
  final SttService sttService;
  final TtsService ttsService;
  final IntentParserService parser;

  VoiceAssistantCubit({
    required this.sttService,
    required this.ttsService,
    required this.parser,
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
      onResult: (text, isFinal) {}, // text is read on release via lastText
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

    final command = parser.parse(trimmed);
    await _handleCommand(command);
    emit(VoiceIdle());
  }

  Future<void> _handleCommand(VoiceCommand command) async {
    switch (command.type) {
      case VoiceCommandType.navigate:
        final destination = command.argument ?? '';
        final text = 'Navigating to $destination';
        _lastInstruction = text;
        emit(VoiceSpeaking(text));
        await ttsService.speak(text);
        break;

      case VoiceCommandType.moreInfo:
        const text =
            'Available commands are navigate to destination, repeat, and more info';
        _lastInstruction = text;
        emit(VoiceSpeaking(text));
        await ttsService.speak(text);
        break;

      case VoiceCommandType.repeat:
        emit(VoiceSpeaking(_lastInstruction));
        await ttsService.speak(_lastInstruction);
        break;

      case VoiceCommandType.unknownLocation:
        const text = 'Sorry, I couldn\'t find that location';
        emit(VoiceSpeaking(text));
        await ttsService.speak(text);
        break;

      case VoiceCommandType.unknown:
        const text = 'Sorry, I didn\'t understand that';
        emit(VoiceSpeaking(text));
        await ttsService.speak(text);
        break;    }
        }
}