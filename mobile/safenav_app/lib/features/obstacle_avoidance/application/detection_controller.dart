/// Lets the voice command handler start/stop obstacle detection without
/// depending on the concrete listener (which is constructed later, with the
/// voice cubit). Implemented by ObstacleListenerService.
abstract class DetectionController {
  /// Whether obstacle-frame streaming is currently active.
  bool get isDetecting;

  /// Starts detection. Returns true if it actually started (camera + server
  /// available).
  Future<bool> startDetection();

  /// Stops detection.
  Future<void> stopDetection();
}
