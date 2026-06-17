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

    final current = _currentRequest!;

    if (_shouldPreempt(incoming, current)) {
      await ttsService.stop();
      _currentRequest = null;

      final isStaleNavigation =
          incoming.priority == SpeechPriority.navigation &&
              current.priority == SpeechPriority.navigation;
      if (!isStaleNavigation) {
        _insertByPriority(current);
      }

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

  bool _shouldPreempt(SpeechRequest incoming, SpeechRequest current) {
    if (incoming.priority == SpeechPriority.obstacle) {
      return current.priority == SpeechPriority.navigation;
    }
    if (incoming.priority == SpeechPriority.navigation) {
      return current.priority == SpeechPriority.navigation;
    }
    return false;
  }

  Future<void> stopAll() async {
    await ttsService.stop();
    _queue.clear();
    _currentRequest = null;
    onIdle();
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
