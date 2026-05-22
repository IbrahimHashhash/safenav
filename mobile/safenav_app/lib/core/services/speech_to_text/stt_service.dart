abstract class SttService {
  Future<bool> initialize();

  Future<void> startListening({
    required Function(String text, bool isFinal) onResult,

    /// Called when the engine stops on its own (silence timeout or
    /// max-duration cap) rather than because we asked it to.
    required Function() onTimeout,

    /// Called on engine errors — permission revoked, mic busy, network
    /// failure for cloud STT, etc. The caller should not restart on this.
    required Function(String message) onError,
  });

  Future<void> stopListening();

  bool get isListening;
}
