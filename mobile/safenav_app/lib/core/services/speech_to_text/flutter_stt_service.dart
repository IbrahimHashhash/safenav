import 'dart:async';
import 'package:azure_stt_flutter/azure_stt_flutter.dart';
import 'stt_service.dart';

class FlutterSttService implements SttService {
  final AzureSpeechToText _azureStt;
  StreamSubscription? _subscription;
  String _lastText = '';
  static const _silenceThreshold = Duration(milliseconds: 800);

  Timer? _silenceTimer;
  Function(String text, bool isFinal)? _pendingOnResult;

  FlutterSttService(this._azureStt);

  @override
  bool get isListening => _azureStt.isListening;

  String get lastText => _lastText;

  @override
  Future<bool> initialize() async => true;

  @override
  Future<void> startListening({
    required Function(String text, bool isFinal) onResult,
    required Function() onTimeout,
    required Function(String message) onError,
  }) async {
    await _subscription?.cancel();
    _silenceTimer?.cancel();
    _lastText = '';
    _pendingOnResult = onResult;

    _subscription = _azureStt.transcriptionStateStream.listen(
      (state) {
        final text = state.text;
        if (text.isNotEmpty) {
          _lastText = text;

          onResult(text, false);

          _silenceTimer?.cancel();
          _silenceTimer = Timer(_silenceThreshold, () {
            _pendingOnResult?.call(_lastText, true);
          });
        }
      },
      onError: (e) => onError(e.toString()),
      onDone: onTimeout,
    );

    await _azureStt.startListening();
  }

  @override
  Future<void> stopListening() async {
    _silenceTimer?.cancel();
    _pendingOnResult = null;

    await _azureStt.stopListening();
    await _subscription?.cancel();
  }

  void dispose() {
    _silenceTimer?.cancel();
    _azureStt.dispose();
  }
}