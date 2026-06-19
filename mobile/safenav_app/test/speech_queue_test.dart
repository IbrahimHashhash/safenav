import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safenav_app/core/services/text_to_speech/tts_service.dart';
import 'package:safenav_app/features/voice_interaction/application/speech_queue.dart';

/// Fake TTS that lets the test control when an utterance "finishes".
class _FakeTts implements TtsService {
  final List<String> spoken = [];
  VoidCallback? _onComplete;

  @override
  Future<void> speak(String text, {VoidCallback? onComplete}) async {
    spoken.add(text);
    _onComplete = onComplete;
  }

  void finishCurrent() {
    final cb = _onComplete;
    _onComplete = null;
    cb?.call();
  }

  @override
  Future<void> stop() async {
    _onComplete = null;
  }
}

void main() {
  group('SpeechQueue latest-wins', () {
    test('keeps only the newest pending obstacle instruction', () async {
      final tts = _FakeTts();
      final queue = SpeechQueue(
        ttsService: tts,
        onSpeaking: (_) {},
        onIdle: () {},
      );

      // A starts speaking immediately.
      await queue.enqueue(const SpeechRequest('A', SpeechPriority.obstacle));
      // B and C queue while A is speaking; only the latest (C) should remain.
      await queue.enqueue(const SpeechRequest('B', SpeechPriority.obstacle));
      await queue.enqueue(const SpeechRequest('C', SpeechPriority.obstacle));

      expect(tts.spoken, ['A']);

      tts.finishCurrent(); // A done -> next should be C, not B
      expect(tts.spoken, ['A', 'C']);

      tts.finishCurrent(); // nothing else queued
      expect(tts.spoken, ['A', 'C']);
    });

    test('obstacle preempts a queued navigation instruction', () async {
      final tts = _FakeTts();
      final queue = SpeechQueue(
        ttsService: tts,
        onSpeaking: (_) {},
        onIdle: () {},
      );

      await queue.enqueue(const SpeechRequest('speaking', SpeechPriority.assistant));
      await queue.enqueue(const SpeechRequest('nav', SpeechPriority.navigation));
      await queue.enqueue(const SpeechRequest('obstacle', SpeechPriority.obstacle));

      // obstacle (highest priority) should be spoken before navigation.
      tts.finishCurrent();
      expect(tts.spoken, ['speaking', 'obstacle']);
      tts.finishCurrent();
      expect(tts.spoken, ['speaking', 'obstacle', 'nav']);
    });
  });
}
