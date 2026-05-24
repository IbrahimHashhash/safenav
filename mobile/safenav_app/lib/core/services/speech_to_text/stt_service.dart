abstract class SttService {
  Future<bool> initialize();

  Future<void> startListening({
    required Function(String text, bool isFinal) onResult,
    required Function() onTimeout,

    required Function(String message) onError,
  });

  Future<void> stopListening();

  bool get isListening;
}
