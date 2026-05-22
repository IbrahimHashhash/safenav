abstract class SttService {
  Future<bool> initialize();

  Future<void> startListening({
    required Function(String text) onResult,
  });

  Future<void> stopListening();

  bool get isListening;
}