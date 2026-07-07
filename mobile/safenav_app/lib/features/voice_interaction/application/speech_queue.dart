import '../../../core/services/text_to_speech/tts_service.dart';

enum SpeechPriority {
  obstacle,
  navigation,
  assistant,
}

class SpeechRequest {
  final String text;
  final SpeechPriority priority;

  
  
  final void Function()? onDone;

  const SpeechRequest(this.text, this.priority, {this.onDone});
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
    final current = _currentRequest;
    if (current == null) return;
    await ttsService.stop();
    _currentRequest = null;
    current.onDone?.call();
    if (_queue.isEmpty) {
      onIdle();
      return;
    }
    await _speakNow(_queue.removeAt(0));
  }

  
  
  
  Future<void> clearNonAssistant() async {
    _queue.removeWhere((r) => r.priority != SpeechPriority.assistant);
    final current = _currentRequest;
    if (current != null && current.priority != SpeechPriority.assistant) {
      await ttsService.stop();
      _currentRequest = null;
      current.onDone?.call();
      if (_queue.isNotEmpty) {
        await _speakNow(_queue.removeAt(0));
      } else {
        onIdle();
      }
    }
  }

  
  
  
  Future<void> clearAll() async {
    _queue.clear();
    final current = _currentRequest;
    if (current != null) {
      await ttsService.stop();
      _currentRequest = null;
      current.onDone?.call();
    }
  }

  Future<void> _speakNow(SpeechRequest request) async {
    _currentRequest = request;
    onSpeaking(request.text);
    ttsService.speak(request.text, onComplete: _onComplete);
  }

  void _onComplete() {
    final done = _currentRequest?.onDone;
    _currentRequest = null;
    done?.call();
    if (_queue.isEmpty) {
      onIdle();
      return;
    }
    _speakNow(_queue.removeAt(0));
  }
}
