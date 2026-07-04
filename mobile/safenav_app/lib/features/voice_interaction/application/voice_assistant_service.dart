import 'package:audioplayers/audioplayers.dart';
import '../../mapbox_navigation/application/navigation_service.dart';
import '../../obstacle_avoidance/application/detection_controller.dart';
import '../../../core/constants/help_info_messages.dart';
import '../../../core/services/profile/user_profile_service.dart';
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
  final UserProfileService _userProfile;

  late final SpeechQueue _speechQueue;
  late final VoiceCommandHandler _commandHandler;
  final AudioPlayer _cuePlayer = AudioPlayer();

  String _lastInstruction = '';
  bool _isPressActive = false;
  bool _hasHandledCommand = false;

  /// While true, the user is in a conversation with the assistant (from the
  /// moment listening starts until the assistant's reply finishes speaking).
  /// Navigation/obstacle guidance is DROPPED during this window so nothing
  /// interrupts the user or the reply. Guarded by a token so a stale reply
  /// completion can't end a newer conversation.
  bool _conversationActive = false;
  int _conversationId = 0;

  Future<void> _sttQueue = Future<void>.value();

  void Function(VoiceAssistantState)? onStateChange;

  VoiceAssistantService({
    required SttService sttService,
    required TtsService ttsService,
    required ParseIntentUseCase parseIntent,
    required ExtractLocationUseCase extractLocation,
    required NavigationService navigationService,
    required UserProfileService userProfile,
  })  : _sttService = sttService,
        _ttsService = ttsService,
        _parseIntent = parseIntent,
        _extractLocation = extractLocation,
        _navigationService = navigationService,
        _userProfile = userProfile {
    _speechQueue = SpeechQueue(
      ttsService: _ttsService,
      onSpeaking: (text) => onStateChange?.call(VoiceSpeaking(text)),
      onIdle: () => onStateChange?.call(VoiceIdle()),
    );
    _commandHandler = VoiceCommandHandler(
      parseIntent: _parseIntent,
      extractLocation: _extractLocation,
      navigationService: _navigationService,
      userProfile: _userProfile,
    );
  }

  Future<void> initialize() async {
    // The cue is a short UI blip. Configure its player to NOT participate in
    // audio focus (mixWithOthers -> AndroidAudioFocus.none). Otherwise, when
    // the recorder or TTS grabs audio focus, audioplayers receives
    // AUDIOFOCUS_LOSS and pauses the cue mid-playback — which made the
    // start/stop cues play only randomly.
    try {
      await _cuePlayer.setAudioContext(
        AudioContextConfig(focus: AudioContextConfigFocus.mixWithOthers).build(),
      );
    } catch (_) {}
    await _sttService.initialize();
  }

  /// Speaks the welcome + how-to message (used on app launch and via "more
  /// info"). Routed through the assistant speech path so guidance never talks
  /// over it, and it becomes the "repeat" target until something else is said.
  Future<void> playWelcome() => _speakReply(HelpInfoMessages.availableCommands);

  /// Attaches the obstacle-detection controller so voice commands can toggle
  /// detection. Wired after the listener is constructed.
  set detectionController(DetectionController controller) {
    _commandHandler.detection = controller;
  }

  Future<void> speakObstacleInstruction(String text) async {
    if (text.trim().isEmpty) return;
    await _enqueueGuidance(SpeechRequest(text, SpeechPriority.obstacle));
  }

  Future<void> speakNavigationInstruction(String text) async {
    if (text.trim().isEmpty) return;
    await _enqueueGuidance(SpeechRequest(text, SpeechPriority.navigation));
  }

  /// Guidance (obstacle/navigation) is DROPPED while the user is conversing
  /// with the assistant, so it never interrupts the command or the reply.
  Future<void> _enqueueGuidance(SpeechRequest request) async {
    if (_conversationActive) return;
    // Track the most recent line actually spoken (guidance OR assistant reply)
    // so "repeat" replays whatever the user last heard — navigation, obstacle,
    // or an assistant response.
    _lastInstruction = request.text;
    await _speechQueue.enqueue(request);
  }

  void _endConversation([int? id]) {
    if (id == null || id == _conversationId) {
      _conversationActive = false;
    }
  }

  Future<void> startListening() async {
    if (_isPressActive) return;

    _isPressActive = true;
    _hasHandledCommand = false;
    // Open a fresh conversation window and silence any guidance currently
    // playing so it never talks over the user.
    _conversationId++;
    _conversationActive = true;
    // Silence ANY speech currently playing (guidance or an assistant reply) so
    // pushing to talk always interrupts and lets the user speak.
    await _speechQueue.clearAll();

    await _playCue();
    if (!_isPressActive) return;

    // Let the activation cue finish before opening the mic, so speaker output
    // never overlaps microphone capture (overlap can disrupt recording on
    // Android). The cue is the user's "speak now" signal anyway.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (!_isPressActive) return;

    // Pre-roll buffer: start capturing into a buffer NOW, before Azure is
    // connected, so the first word spoken right after the cue isn't lost during
    // the ~1s the session takes to come online. Azure receives the buffered
    // audio first, then live audio, once it connects.
    try {
      await _runStt(() => _sttService.primeMic());
    } catch (e) {
      _onSttError('Microphone error: $e');
      return;
    }
    if (!_isPressActive) return;

    onStateChange?.call(VoiceListening());

    await _runStt(
      () => _sttService.startListening(
        onResult: (text, isFinal) {
          if (isFinal && _isPressActive && !_hasHandledCommand) {
            _isPressActive = false;
            _hasHandledCommand = true;
            _runStt(() => _sttService.stopListening()).then((_) {
              _handleRecognizedText(text);
            });
          }
        },
        onTimeout: _onSttTimeout,
        onError: _onSttError,
      ),
    );
  }

  Future<void> _runStt(Future<void> Function() action) {
    final result = _sttQueue.then((_) => action());
    _sttQueue = result.catchError((_) {});
    return result;
  }

  Future<void> _playCue({double rate = 1.0, double volume = 1.0}) async {
    try {
      await _cuePlayer.setPlaybackRate(rate);
      await _cuePlayer.setVolume(volume);
      await _cuePlayer.play(AssetSource('sounds/activation.wav'));
    } catch (_) {}
  }

  Future<void> cancelListening() async {
    _isPressActive = false;
    _hasHandledCommand = true;
    await _runStt(() => _sttService.stopListening());
    await _playCue(rate: 1.25, volume: 0.55);
    _endConversation();
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
      _endConversation();
      onStateChange?.call(VoiceIdle());
    }
  }

  void _onSttError(String message) {
    if (!_isPressActive) return;
    _isPressActive = false;
    _endConversation();
    onStateChange?.call(VoiceError(message));
  }

  Future<void> _handleRecognizedText(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      _endConversation();
      _emitIdleIfQuiet();
      return;
    }

    // Surface the recognized transcript so the UI can caption the input.
    onStateChange?.call(VoiceProcessing(trimmed));

    if (_parseIntent(trimmed) == VoiceCommandType.repeat) {
      if (_lastInstruction.isNotEmpty) {
        await _speakReply(_lastInstruction);
      } else {
        _endConversation();
        _emitIdleIfQuiet();
      }
      return;
    }

    final request = await _commandHandler.handle(trimmed);
    if (request.text.isEmpty) {
      _endConversation();
      _emitIdleIfQuiet();
      return;
    }

    await _speakReply(request.text);
  }

  /// Speaks the assistant's reply and ends the conversation window once the
  /// reply has finished (so guidance resumes only after the user is answered).
  Future<void> _speakReply(String text) async {
    _lastInstruction = text;
    final id = _conversationId;
    await _speechQueue.enqueue(
      SpeechRequest(
        text,
        SpeechPriority.assistant,
        onDone: () => _endConversation(id),
      ),
    );
  }

  void _emitIdleIfQuiet() {
    if (!_speechQueue.isActive) onStateChange?.call(VoiceIdle());
  }

  void dispose() {
    _navigationService.dispose();
    _cuePlayer.dispose();
  }
}
