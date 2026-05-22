abstract class TtsService {
  Future<void> speak(String text);

  Future<void> stop();
}