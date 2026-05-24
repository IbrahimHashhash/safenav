import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'tts_config.dart';
import 'tts_service.dart';

class FlutterTtsService implements TtsService {
  final FlutterTts _tts;
  final TtsConfig config;

  FlutterTtsService(this._tts, {this.config = const TtsConfig()});

  Future<void> _applyConfig() async {
    await _tts.setLanguage(config.language);
    await _tts.setSpeechRate(config.speechRate);
    await _tts.setPitch(config.pitch);
    await _tts.setVolume(config.volume);
  }

  @override
  Future<void> speak(String text, {VoidCallback? onComplete}) async {
    _tts.setCompletionHandler(() {}); 
    await _tts.stop();
    await _applyConfig();
    _tts.setCompletionHandler(() {
      onComplete?.call();
    });
    await _tts.speak(text);
  }

  @override
  Future<void> stop() async {
    _tts.setCompletionHandler(() {}); 
    await _tts.stop();
  }
}