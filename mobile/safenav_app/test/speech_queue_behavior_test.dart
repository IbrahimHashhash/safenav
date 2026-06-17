import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safenav_app/features/voice_interaction/application/speech_queue.dart';
import 'package:safenav_app/core/services/text_to_speech/tts_service.dart';

class FakeTts implements TtsService {
  VoidCallback? _onComplete;
  String? speaking;
  final List<String> stopped = [];
  final List<String> started = [];

  @override
  Future<void> speak(String text, {VoidCallback? onComplete}) async {
    speaking = text;
    started.add(text);
    _onComplete = onComplete;
  }

  @override
  Future<void> stop() async {
    if (speaking != null) stopped.add(speaking!);
    speaking = null;
    _onComplete = null;
  }

  void finish() {
    final cb = _onComplete;
    speaking = null;
    _onComplete = null;
    cb?.call();
  }
}

void main() {
  test('navigation does not cut a playing assistant response', () async {
    final tts = FakeTts();
    final q = SpeechQueue(ttsService: tts, onSpeaking: (_) {}, onIdle: () {});
    await q.enqueue(const SpeechRequest('navigation started', SpeechPriority.assistant));
    await q.enqueue(const SpeechRequest('turn right', SpeechPriority.navigation));
    expect(tts.speaking, 'navigation started');
    expect(tts.stopped.contains('navigation started'), isFalse);
    tts.finish();
    expect(tts.speaking, 'turn right');
  });

  test('obstacle does not interrupt a playing assistant response', () async {
    final tts = FakeTts();
    final q = SpeechQueue(ttsService: tts, onSpeaking: (_) {}, onIdle: () {});
    await q.enqueue(const SpeechRequest('list of locations', SpeechPriority.assistant));
    await q.enqueue(const SpeechRequest('obstacle ahead', SpeechPriority.obstacle));
    expect(tts.speaking, 'list of locations');
    expect(tts.stopped.contains('list of locations'), isFalse);
    tts.finish();
    expect(tts.speaking, 'obstacle ahead');
  });

  test('obstacle cuts a playing navigation instruction', () async {
    final tts = FakeTts();
    final q = SpeechQueue(ttsService: tts, onSpeaking: (_) {}, onIdle: () {});
    await q.enqueue(const SpeechRequest('turn left', SpeechPriority.navigation));
    await q.enqueue(const SpeechRequest('stop now', SpeechPriority.obstacle));
    expect(tts.stopped.contains('turn left'), isTrue);
    expect(tts.speaking, 'stop now');
  });

  test('interrupted navigation is re-queued and replayed after obstacle', () async {
    final tts = FakeTts();
    var idle = false;
    final q = SpeechQueue(
      ttsService: tts,
      onSpeaking: (_) {},
      onIdle: () => idle = true,
    );
    await q.enqueue(const SpeechRequest('turn left', SpeechPriority.navigation));
    await q.enqueue(const SpeechRequest('obstacle ahead', SpeechPriority.obstacle));
    expect(tts.speaking, 'obstacle ahead');

    tts.finish();
    expect(tts.speaking, 'turn left');

    tts.finish();
    expect(idle, isTrue);
  });

  test('newer navigation replaces a playing navigation instruction', () async {
    final tts = FakeTts();
    final q = SpeechQueue(ttsService: tts, onSpeaking: (_) {}, onIdle: () {});
    await q.enqueue(const SpeechRequest('in 50 meters turn', SpeechPriority.navigation));
    await q.enqueue(const SpeechRequest('in 20 meters turn', SpeechPriority.navigation));
    expect(tts.stopped.contains('in 50 meters turn'), isTrue);
    expect(tts.speaking, 'in 20 meters turn');
  });

  test('navigation does not cut a playing obstacle instruction', () async {
    final tts = FakeTts();
    final q = SpeechQueue(ttsService: tts, onSpeaking: (_) {}, onIdle: () {});
    await q.enqueue(const SpeechRequest('obstacle', SpeechPriority.obstacle));
    await q.enqueue(const SpeechRequest('turn right', SpeechPriority.navigation));
    expect(tts.speaking, 'obstacle');
    expect(tts.stopped.contains('obstacle'), isFalse);
    tts.finish();
    expect(tts.speaking, 'turn right');
  });

  test('assistant is never interrupted; queued items drain by priority after it', () async {
    final tts = FakeTts();
    final q = SpeechQueue(ttsService: tts, onSpeaking: (_) {}, onIdle: () {});
    await q.enqueue(const SpeechRequest('assistant msg', SpeechPriority.assistant));
    await q.enqueue(const SpeechRequest('ob1', SpeechPriority.obstacle));
    await q.enqueue(const SpeechRequest('turn right', SpeechPriority.navigation));
    await q.enqueue(const SpeechRequest('ob2', SpeechPriority.obstacle));

    expect(tts.speaking, 'assistant msg');
    expect(tts.stopped.contains('assistant msg'), isFalse);

    tts.finish();
    expect(tts.speaking, 'ob1');
    tts.finish();
    expect(tts.speaking, 'ob2');
    tts.finish();
    expect(tts.speaking, 'turn right');
  });

  test('stale navigation replacement is not re-queued', () async {
    final tts = FakeTts();
    final q = SpeechQueue(ttsService: tts, onSpeaking: (_) {}, onIdle: () {});
    await q.enqueue(const SpeechRequest('in 50 meters turn', SpeechPriority.navigation));
    await q.enqueue(const SpeechRequest('in 20 meters turn', SpeechPriority.navigation));
    expect(tts.speaking, 'in 20 meters turn');
    expect(tts.started.contains('in 50 meters turn'), isTrue);
    tts.finish();
    expect(tts.speaking, isNull);
    expect(tts.started.where((t) => t == 'in 50 meters turn').length, 1);
  });

  test('skipCurrent stops current message but keeps the queue', () async {
    final tts = FakeTts();
    final q = SpeechQueue(ttsService: tts, onSpeaking: (_) {}, onIdle: () {});
    await q.enqueue(const SpeechRequest('list of locations', SpeechPriority.assistant));
    await q.enqueue(const SpeechRequest('ob1', SpeechPriority.obstacle));
    await q.enqueue(const SpeechRequest('turn right', SpeechPriority.navigation));

    await q.skipCurrent();
    expect(tts.stopped.contains('list of locations'), isTrue);
    expect(tts.speaking, 'ob1');

    tts.finish();
    expect(tts.speaking, 'turn right');
  });

  test('skipCurrent with empty queue goes idle', () async {
    final tts = FakeTts();
    var idle = false;
    final q = SpeechQueue(
      ttsService: tts,
      onSpeaking: (_) {},
      onIdle: () => idle = true,
    );
    await q.enqueue(const SpeechRequest('list of locations', SpeechPriority.assistant));
    await q.skipCurrent();
    expect(tts.speaking, isNull);
    expect(idle, isTrue);
  });
}
