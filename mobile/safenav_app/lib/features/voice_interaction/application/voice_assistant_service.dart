import 'package:audioplayers/audioplayers.dart';
import '../../mapbox_navigation/application/navigation_service.dart';
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
  final NavigationService _navigationService;

  late final SpeechQueue _speechQueue;
  late final VoiceCommandHandler _commandHandler;
  final AudioPlayer _cuePlayer = AudioPlayer();

  String _lastInstruction = '';
  bool _isPressActive = false;
  bool _hasHandledCommand = false;
  final List<SpeechRequest> _deferredWhileListening = [];

  void Function(VoiceAssistantState)? onStateChange;

  VoiceAssistantService({
    required SttService sttService,
    required TtsService ttsService,
    required ParseIntentUseCase parseIntent,
    required ExtractLocationUseCase extractLocation,
    required NavigationService navigationService,
  })  : _sttService = sttService,
        _ttsService = ttsService,
        _parseIntent = parseIntent,
        _extractLocation = extractLocation,
        _navigationService = navigationService {
    _speechQueue = SpeechQueue(
      ttsService: _ttsService,
      onSpeaking: (text) => onStateChange?.call(VoiceSpeaking(text)),
      onIdle: () => onStateChange?.call(VoiceIdle()),
    );
    _commandHandler = VoiceCommandHandler(
      parseIntent: _parseIntent,
      extractLocation: _extractLocation,
      navigationService: _navigationService,
    );
  }

  Future<void> initialize() => _sttService.initialize();

  Future<void> speakObstacleInstruction(String text) async {
    if (text.trim().isEmpty) return;
    await _enqueueOrDefer(SpeechRequest(text, SpeechPriority.obstacle));
  }

  Future<void> speakNavigationInstruction(String text) async {
    if (text.trim().isEmpty) return;
    await _enqueueOrDefer(SpeechRequest(text, SpeechPriority.navigation));
  }

  Future<void> _enqueueOrDefer(SpeechRequest request) async {
    if (_isPressActive) {
      if (request.priority == SpeechPriority.navigation) {
        _deferredWhileListening
            .removeWhere((r) => r.priority == SpeechPriority.navigation);
      }
      _deferredWhileListening.add(request);
      return;
    }
    await _speechQueue.enqueue(request);
  }

  Future<void> _flushDeferred() async {
    if (_deferredWhileListening.isEmpty) return;
    final pending = List<SpeechRequest>.from(_deferredWhileListening);
    _deferredWhileListening.clear();
    for (final request in pending) {
      await _speechQueue.enqueue(request);
    }
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
          _sttService.stopListening().then((_) {
            _flushDeferred();
            _handleRecognizedText(text);
          });
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
    _isPressActive = false;
    _hasHandledCommand = true;
    await _sttService.stopListening();
    final hadDeferred = _deferredWhileListening.isNotEmpty;
    _flushDeferred();
    if (!hadDeferred) onStateChange?.call(VoiceIdle());
  }

  void _onSttTimeout() {
    if (!_isPressActive || _hasHandledCommand) return;
    _isPressActive = false;

    final text = (_sttService as FlutterSttService).lastText;
    final hadDeferred = _deferredWhileListening.isNotEmpty;
    _flushDeferred();
    if (text.isNotEmpty) {
      _hasHandledCommand = true;
      _handleRecognizedText(text);
    } else if (!hadDeferred) {
      onStateChange?.call(VoiceIdle());
    }
  }

  void _onSttError(String message) {
    if (!_isPressActive) return;
    _isPressActive = false;
    final hadDeferred = _deferredWhileListening.isNotEmpty;
    _flushDeferred();
    if (!hadDeferred) onStateChange?.call(VoiceError(message));
  }

  Future<void> stopSpeaking() => _speechQueue.skipCurrent();

  Future<void> _handleRecognizedText(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      if (!_speechQueue.isActive) onStateChange?.call(VoiceIdle());
      return;
    }

    if (_parseIntent(trimmed) == VoiceCommandType.repeat) {
      if (_lastInstruction.isNotEmpty) {
        await _speechQueue.enqueue(
          SpeechRequest(_lastInstruction, SpeechPriority.assistant),
        );
      } else if (!_speechQueue.isActive) {
        onStateChange?.call(VoiceIdle());
      }
      return;
    }

    final request = await _commandHandler.handle(trimmed);
    if (request.text.isEmpty) {
      if (!_speechQueue.isActive) onStateChange?.call(VoiceIdle());
      return;
    }

    _lastInstruction = request.text;
    await _speechQueue.enqueue(request);
  }

  void dispose() {
    _navigationService.dispose();
    _cuePlayer.dispose();
  }
}
