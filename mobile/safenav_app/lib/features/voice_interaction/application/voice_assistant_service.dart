import 'package:audioplayers/audioplayers.dart';
import '../../../core/services/speech_to_text/flutter_stt_service.dart';
import '../../../core/services/speech_to_text/stt_service.dart';
import '../../../core/services/text_to_speech/tts_service.dart';
import '../domain/entities/voice_command.dart';
import '../domain/usecases/extract_location_usecase.dart';
import '../domain/usecases/parse_intent_usecase.dart';
import '../presentation/cubit/voice_assistant_state.dart';
import 'speech_queue.dart';
import 'voice_command_handler.dart';

class VoiceAssistantService {
  final SttService _sttService;
  final TtsService _ttsService;
  final ParseIntentUseCase _parseIntent;
  final ExtractLocationUseCase _extractLocation;

  late final SpeechQueue _speechQueue;
  late final VoiceCommandHandler _commandHandler;
  final AudioPlayer _cuePlayer = AudioPlayer();

  String _lastInstruction = '';
  bool _isPressActive = false;
  bool _hasHandledCommand = false;

  void Function(VoiceAssistantState)? onStateChange;

  VoiceAssistantService({
    required SttService sttService,
    required TtsService ttsService,
    required ParseIntentUseCase parseIntent,
    required ExtractLocationUseCase extractLocation,
  })  : _sttService = sttService,
        _ttsService = ttsService,
        _parseIntent = parseIntent,
        _extractLocation = extractLocation {
    _speechQueue = SpeechQueue(
      ttsService: _ttsService,
      onSpeaking: (text) => onStateChange?.call(VoiceSpeaking(text)),
      onIdle: () => onStateChange?.call(VoiceIdle()),
    );
    _commandHandler = VoiceCommandHandler(
      parseIntent: _parseIntent,
      extractLocation: _extractLocation,
    );
  }

  Future<void> initialize() => _sttService.initialize();

  Future<void> speakObstacleInstruction(String text) async {
    if (text.trim().isEmpty) return;

    if (_isPressActive) {
      _isPressActive = false;
      _hasHandledCommand = true;
      await _sttService.stopListening();
    }

    await _speechQueue.enqueue(SpeechRequest(text, SpeechPriority.obstacle));
  }

  Future<void> speakNavigationInstruction(String text) async {
    if (text.trim().isEmpty) return;
    await _speechQueue.enqueue(SpeechRequest(text, SpeechPriority.navigation));
  }

  Future<void> startListening() async {
    if (_isPressActive || _sttService.isListening) return;

    _isPressActive = true;
    _hasHandledCommand = false;
    await _cueListeningStarted();

    onStateChange?.call(VoiceListening());

    await _sttService.startListening(
      onResult: (text, isFinal) {
        if (isFinal && _isPressActive && !_hasHandledCommand) {
          _isPressActive = false;
          _hasHandledCommand = true;
          _sttService.stopListening().then((_) => _handleRecognizedText(text));
        }
      },
      onTimeout: _onSttTimeout,
      onError: _onSttError,
    );
  }

  Future<void> _cueListeningStarted() async {
    try {
      await _cuePlayer.play(AssetSource('sounds/activation.wav'));
    } catch (_) {}
  }

  Future<void> cancelListening() async {
    if (!_isPressActive) return;

    _isPressActive = false;
    _hasHandledCommand = true;
    await _sttService.stopListening();
    onStateChange?.call(VoiceIdle());
  }

  void _onSttTimeout() {
    if (!_isPressActive || _hasHandledCommand) return;
    _isPressActive = false;

    final text = (_sttService as FlutterSttService).lastText;
    if (text.isNotEmpty) {
      _hasHandledCommand = true;
      _handleRecognizedText(text);
    } else {
      onStateChange?.call(VoiceIdle());
    }
  }

  void _onSttError(String message) {
    if (!_isPressActive) return;
    _isPressActive = false;
    onStateChange?.call(VoiceError(message));
  }

  Future<void> stopSpeaking() => _speechQueue.stopAll();

  Future<void> _handleRecognizedText(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      onStateChange?.call(VoiceIdle());
      return;
    }

    if (_parseIntent(trimmed) == VoiceCommandType.repeat) {
      if (_lastInstruction.isNotEmpty) {
        await _speechQueue.enqueue(
          SpeechRequest(_lastInstruction, SpeechPriority.assistant),
        );
      } else {
        onStateChange?.call(VoiceIdle());
      }
      return;
    }

    final request = _commandHandler.handle(trimmed);
    if (request.text.isEmpty) {
      onStateChange?.call(VoiceIdle());
      return;
    }

    _lastInstruction = request.text;
    await _speechQueue.enqueue(request);
  }

  void dispose() {
    _cuePlayer.dispose();
  }
}
