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
        final text = state.text;
        if (text.isNotEmpty) {
          _lastText = text;
          print('[STT] captured: "$text"');

          onResult(text, false); 
        }
      },
      onError: (e) => onError(e.toString()),
      onDone: onTimeout,
    );

    await _azureStt.startListening();
  }

  @override
  Future<void> stopListening() async {
    await _subscription?.cancel();
    await _azureStt.stopListening();
  }

  String get lastText => _lastText;

  void dispose() => _azureStt.dispose();
}