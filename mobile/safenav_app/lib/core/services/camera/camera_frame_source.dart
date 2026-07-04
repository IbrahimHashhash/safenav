import 'dart:typed_data';

import 'package:flutter/widgets.dart';






abstract class CameraFrameSource {
  
  bool get isReady;

  
  Size? get previewSize;

  
  
  Future<bool> initialize();

  
  
  Future<Uint8List?> captureJpeg();

  
  
  Widget buildPreview({Widget? placeholder});

  
  Future<void> dispose();
}
