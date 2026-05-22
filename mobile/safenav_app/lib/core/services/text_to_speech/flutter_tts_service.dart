import 'package:flutter_tts/flutter_tts.dart';

import 'tts_service.dart';

class FlutterTtsService implements TtsService {
  final FlutterTts _tts;

  FlutterTtsService(this._tts);

  @override
  Future<void> speak(String text) async {
    await _tts.stop();

    await _tts.speak(text);
  }

  @override
  Future<void> stop() async {
    await _tts.stop();
  }
}