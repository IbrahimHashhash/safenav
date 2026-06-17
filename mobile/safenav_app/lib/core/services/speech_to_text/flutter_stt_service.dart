import 'dart:async';
import 'package:azure_stt_flutter/azure_stt_flutter.dart';
import 'stt_service.dart';

class FlutterSttService implements SttService {
  final AzureSpeechToText _azureStt;
  StreamSubscription? _subscription;
  String _lastText = '';

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
    _lastText = '';

    _subscription = _azureStt.transcriptionStateStream.listen(
      (state) {
        final intermediate = state.intermediateText.trim();
        if (intermediate.isNotEmpty) {
          onResult(intermediate, false);
        }

        final finalized = state.finalizedText.join(' ').trim();
        if (finalized.isNotEmpty) {
          _lastText = finalized;
          onResult(finalized, true);
        }
      },
      onError: (e) => onError(e.toString()),
      onDone: onTimeout,
    );

    await _azureStt.startListening();
  }

  @override
  Future<void> stopListening() async {
    await _azureStt.stopListening();
    await _subscription?.cancel();
  }

  void dispose() {
    _azureStt.dispose();
  }
}
