import 'package:flutter_tts/flutter_tts.dart';
import 'tts_config.dart';
import 'tts_service.dart';

class FlutterTtsService implements TtsService {
  final FlutterTts _tts;
  final TtsConfig config;  // ← missing this line

  FlutterTtsService(this._tts, {this.config = const TtsConfig()});

  Future<void> _applyConfig() async {
    await _tts.setLanguage(config.language);
    await _tts.setSpeechRate(config.speechRate);
    await _tts.setPitch(config.pitch);
    await _tts.setVolume(config.volume);
  }

  @override
  Future<void> speak(String text) async {
    await _tts.stop();
    await _applyConfig();  // ← also wire this in
    await _tts.speak(text);
  }

  @override
  Future<void> stop() async {
    await _tts.stop();
  }
}