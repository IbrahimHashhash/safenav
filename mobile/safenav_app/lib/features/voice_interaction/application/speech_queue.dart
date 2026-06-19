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
    // Obstacle and navigation guidance is only useful when fresh. Keep at most
    // the newest pending request of that kind so the TTS never works through a
    // backlog of stale instructions (e.g. warning about a chair that has since
    // left the frame).
    if (incoming.priority == SpeechPriority.navigation ||
        incoming.priority == SpeechPriority.obstacle) {
      _queue.removeWhere((r) => r.priority == incoming.priority);
    }

    if (_currentRequest == null) {
      await _speakNow(incoming);
      return;
    }

    _insertByPriority(incoming);
  }

  void _insertByPriority(SpeechRequest request) {
    var i = 0;
    while (i < _queue.length &&
        _queue[i].priority.index <= request.priority.index) {
      i++;
    }
    _queue.insert(i, request);
  }

  Future<void> skipCurrent() async {
    if (_currentRequest == null) return;
    await ttsService.stop();
    _currentRequest = null;
    if (_queue.isEmpty) {
      onIdle();
      return;
    }
    await _speakNow(_queue.removeAt(0));
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
