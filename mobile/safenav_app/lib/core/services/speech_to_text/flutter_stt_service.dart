import 'package:speech_to_text/speech_to_text.dart';

import 'stt_service.dart';

class FlutterSttService implements SttService {
  final SpeechToText _speech;

  /// True while a user-initiated session is active. Used to distinguish
  /// "engine stopped because we asked" from "engine stopped on its own."
  bool _sessionActive = false;

  /// Set once per session when the engine signals end-of-session, so the
  /// `done` and `notListening` status events don't both fire onTimeout.
  bool _stopFired = false;

  /// Live callbacks for the current session. Rewired on every startListening.
  Function()? _onTimeout;
  Function(String)? _onError;

  FlutterSttService(this._speech);

  @override
  bool get isListening => _speech.isListening;

  @override
  Future<bool> initialize() async {
    return await _speech.initialize(
      onStatus: _handleStatus,
      onError: _handleError,
    );
  }

  void _handleStatus(String status) {
    if (!_sessionActive) return;
    // We only react to 'done'. `notListening` fires *before* the final
    // result is delivered, so reacting to it would lose the last word or
    // two. `done` fires once the engine has fully wound the session down.
    if (status != 'done') return;
    if (_stopFired) return;

    _stopFired = true;
    _sessionActive = false;
    _onTimeout?.call();
  }

  void _handleError(dynamic error) {
    if (!_sessionActive) return;
    _sessionActive = false;
    final message = error?.errorMsg?.toString() ?? error.toString();
    _onError?.call(message);
  }

  @override
  Future<void> startListening({
    required Function(String text, bool isFinal) onResult,
    required Function() onTimeout,
    required Function(String message) onError,
  }) async {
    _onTimeout = onTimeout;
    _onError = onError;
    _stopFired = false;
    _sessionActive = true;

    try {
      await _listenOnce(onResult);
    } catch (e) {
      // Plugin rejected the call — most often because internal state is
      // stale after a previous abort. Re-initialize and try once more
      // before bubbling up.
      _sessionActive = false;
      final recovered = await _speech.initialize(
        onStatus: _handleStatus,
        onError: _handleError,
      );
      if (!recovered) {
        onError('Microphone unavailable');
        return;
      }
      _sessionActive = true;
      _stopFired = false;
      try {
        await _listenOnce(onResult);
      } catch (e2) {
        _sessionActive = false;
        onError('Microphone unavailable');
      }
    }
  }

  Future<void> _listenOnce(Function(String, bool) onResult) {
    return _speech.listen(
      onResult: (result) {
        onResult(result.recognizedWords, result.finalResult);
      },
      // Tuned for a hold-to-talk UI: a user reading out a destination may
      // pause to think. When these caps trip, the cubit silently restarts
      // a new session as long as the press is still active.
      listenOptions: SpeechListenOptions(
        listenFor: const Duration(seconds: 60),
        pauseFor: const Duration(seconds: 8),
      ),
    );
  }

  @override
  Future<void> stopListening() async {
    // Mark inactive *before* calling stop so the status callback can tell
    // this is a user-initiated stop, not a timeout.
    _sessionActive = false;
    await _speech.stop();
  }
}
