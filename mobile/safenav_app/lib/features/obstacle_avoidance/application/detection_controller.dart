


abstract class DetectionController {
  
  bool get isDetecting;

  
  
  Future<bool> startDetection();

  
  Future<void> stopDetection();
}
