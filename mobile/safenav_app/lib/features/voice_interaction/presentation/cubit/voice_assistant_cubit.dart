import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/services/intent_parser/intent_parser_service.dart';
import '../../../../core/services/intent_parser/voice_command.dart';
import '../../../../core/services/speech_to_text/stt_service.dart';
import '../../../../core/services/text_to_speech/tts_service.dart';

import 'voice_assistant_state.dart';

class VoiceAssistantCubit extends Cubit<VoiceAssistantState> {
  final SttService sttService;
  final TtsService ttsService;
  final IntentParserService parser;

  /// Cap on how many times the engine can time out *with nothing recognized*
  /// in a row before we give up. As long as the user keeps producing speech,
  /// restarts are unlimited — this counter only ticks up on silent sessions,
  /// which is the signature of a genuinely broken mic.
  static const _maxConsecutiveEmptyRestarts = 5;

  VoiceAssistantCubit({
    required this.sttService,
    required this.ttsService,
    required this.parser,
  }) : super(VoiceIdle());

  /// Transcript accumulated from *completed* engine sessions within the
  /// current press. Each restart concatenates the previous session's final
  /// text here so the live session's partials don't erase earlier speech.
  String _committedText = '';

  /// Live transcript of the *current* engine session. Replaced on each
  /// partial/final result.
  String _sessionText = '';

  String _lastInstruction = '';
  bool _isPressActive = false;
  bool _awaitingFinalResult = false;
  bool _hasHandledCommand = false;
  int _consecutiveEmptyRestarts = 0;

  /// Forces a fresh `sttService.initialize()` before the next listen. Set
  /// after any error or empty-restart give-up so the user's next press
  /// starts from a clean engine state.
  bool _needsReinit = false;

  String get _recognizedText {
    if (_committedText.isEmpty) return _sessionText;
    if (_sessionText.isEmpty) return _committedText;
    return '$_committedText $_sessionText';
  }

  Future<void> initialize() async {
    await sttService.initialize();
  }

  /// USER PRESSES SCREEN
  Future<void> startListening() async {
    if (_isPressActive || sttService.isListening) {
      return;
    }

    _isPressActive = true;
    _awaitingFinalResult = false;
    _hasHandledCommand = false;
    _committedText = '';
    _sessionText = '';
    _consecutiveEmptyRestarts = 0;

    // Re-initialize the engine transparently if the previous session left
    // it in a bad state. The user shouldn't have to know.
    if (_needsReinit) {
      _needsReinit = false;
      await sttService.initialize();
    }

    emit(VoiceListening());

    await _startSttSession();
  }

  /// Starts one engine session. Reused by [startListening] and by the
  /// timeout-recovery path.
  Future<void> _startSttSession() async {
    _sessionText = '';

    await sttService.startListening(
      onResult: (text, isFinal) {
        _sessionText = text;

        if (_awaitingFinalResult && isFinal) {
          _awaitingFinalResult = false;
          _handleRecognizedText();
        }
      },
      onTimeout: _onSttTimeout,
      onError: _onSttError,
    );
  }

  /// Engine stopped on its own — either silence pause or max-duration cap.
  /// If the user is still holding, fold the current session's text into the
  /// committed buffer and restart so they don't lose what they've said.
  Future<void> _onSttTimeout() async {
    // User released between the engine stop and this callback — the
    // stopListening() flow will take it from here.
    if (!_isPressActive) return;
    if (_hasHandledCommand) return;

    final sessionHadSpeech = _sessionText.trim().isNotEmpty;

    // Promote whatever the engine recognized in this session to the
    // committed buffer; the next session starts fresh.
    if (sessionHadSpeech) {
      _committedText = _committedText.isEmpty
          ? _sessionText
          : '$_committedText $_sessionText';
      _consecutiveEmptyRestarts = 0;
    } else {
      _consecutiveEmptyRestarts++;
    }
    _sessionText = '';

    if (_consecutiveEmptyRestarts >= _maxConsecutiveEmptyRestarts) {
      _isPressActive = false;
      _needsReinit = true;
      emit(VoiceError('Microphone stopped responding. Please try again.'));
      return;
    }

    // Yield the microtask queue before restarting. The plugin's status
    // callback is mid-dispatch when this runs; calling listen() synchronously
    // races against the engine's own teardown and causes an instant retry.
    await Future.delayed(const Duration(milliseconds: 150));

    // Re-check the press state — user might have released during the delay.
    if (!_isPressActive || _hasHandledCommand) return;

    await _startSttSession();
  }

  void _onSttError(String message) {
    if (!_isPressActive) return;
    _isPressActive = false;
    _needsReinit = true;
    emit(VoiceError(message));
  }

  /// USER RELEASES SCREEN
  Future<void> stopListening() async {
    if (!_isPressActive) {
      return;
    }

    _isPressActive = false;
    _awaitingFinalResult = true;

    await sttService.stopListening();

    if (_hasHandledCommand) {
      return;
    }

    await Future.delayed(const Duration(milliseconds: 350));

    if (_hasHandledCommand) {
      return;
    }

    _awaitingFinalResult = false;
    await _handleRecognizedText();
  }

  Future<void> _handleRecognizedText() async {
    if (_hasHandledCommand) {
      return;
    }

    final text = _recognizedText.trim();
    _hasHandledCommand = true;

    if (text.isEmpty) {
      emit(VoiceIdle());
      return;
    }

    final command = parser.parse(text);

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

      case VoiceCommandType.unknown:
        const text = 'Sorry command not recognized';

        emit(VoiceSpeaking(text));

        await ttsService.speak(text);

        break;
    }
  }
}
