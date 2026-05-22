import 'package:speech_to_text/speech_to_text.dart';

import 'stt_service.dart';

class FlutterSttService implements SttService {
  final SpeechToText _speech;

  bool _sessionActive = false;

  bool _stopFired = false;

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
      listenOptions: SpeechListenOptions(
        listenFor: const Duration(seconds: 60),
        pauseFor: const Duration(seconds: 8),
      ),
    );
  }

  @override
  Future<void> stopListening() async {
    _sessionActive = false;
    await _speech.stop();
  }
}
