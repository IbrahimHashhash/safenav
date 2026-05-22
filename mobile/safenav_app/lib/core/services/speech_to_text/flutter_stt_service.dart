import 'package:speech_to_text/speech_to_text.dart';

import 'stt_service.dart';

class FlutterSttService implements SttService {
  final SpeechToText _speech;

  FlutterSttService(this._speech);

  @override
  bool get isListening => _speech.isListening;

  @override
  Future<bool> initialize() async {
    return await _speech.initialize();
  }

  @override
  Future<void> startListening({
    required Function(String text) onResult,
  }) async {
    await _speech.listen(
      onResult: (result) {
        onResult(result.recognizedWords);
      },
    );
  }

  @override
  Future<void> stopListening() async {
    await _speech.stop();
  }
}