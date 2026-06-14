import '../../../core/services/text_to_speech/tts_service.dart';

enum SpeechPriority {
  obstacle,
  navigation,
  assistant,
}

class SpeechRequest {
  final String text;
  final SpeechPriority priority;
  const SpeechRequest(this.text, this.priority);
}

class SpeechQueue {
  final TtsService ttsService;
  final void Function(String text) onSpeaking;
  final void Function() onIdle;

  SpeechQueue({
    required this.ttsService,
    required this.onSpeaking,
    required this.onIdle,
  });

  final List<SpeechRequest> _queue = [];
  SpeechRequest? _currentRequest;

  bool get isActive => _currentRequest != null;

  Future<void> enqueue(SpeechRequest incoming) async {
    if (incoming.priority == SpeechPriority.navigation) {
      _queue.removeWhere((r) => r.priority == SpeechPriority.navigation);
    }

    if (_currentRequest == null) {
      await _speakNow(incoming);
      return;
    }

    if (incoming.priority.index < _currentRequest!.priority.index) {
      await ttsService.stop();
      _currentRequest = null;
      await _speakNow(incoming);
      return;
    }

    if (incoming.priority == SpeechPriority.navigation &&
        _currentRequest!.priority == SpeechPriority.navigation) {
      await ttsService.stop();
      _currentRequest = null;
      await _speakNow(incoming);
      return;
    }

    _queue.add(incoming);
    _queue.sort((a, b) => a.priority.index.compareTo(b.priority.index));
  }

  Future<void> stopAll() async {
    await ttsService.stop();
    _queue.clear();
    _currentRequest = null;
    onIdle();
  }

  Future<void> _speakNow(SpeechRequest request) async {
    _currentRequest = request;
    onSpeaking(request.text);
    ttsService.speak(request.text, onComplete: _onComplete);
  }

  void _onComplete() {
    _currentRequest = null;
    if (_queue.isEmpty) {
      onIdle();
      return;
    }
    _speakNow(_queue.removeAt(0));
  }
}
