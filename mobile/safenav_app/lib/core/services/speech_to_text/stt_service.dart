abstract class SttService {
  Future<bool> initialize();

  /// Starts capturing microphone audio into a buffer immediately, BEFORE the
  /// recognizer is connected. This lets audio spoken during connection setup be
  /// retained (a "pre-roll" buffer) so the first word isn't clipped. Must be
  /// called before [startListening].
  Future<void> primeMic();

  Future<void> startListening({
    required Function(String text, bool isFinal) onResult,
    required Function() onTimeout,

    required Function(String message) onError,
  });

  Future<void> stopListening();

  bool get isListening;
}
