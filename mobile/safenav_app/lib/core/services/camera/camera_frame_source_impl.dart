import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/widgets.dart';
import 'package:permission_handler/permission_handler.dart';

import 'camera_frame_source.dart';







class CameraFrameSourceImpl implements CameraFrameSource {
  CameraController? _controller;
  bool _initializing = false;

  @override
  bool get isReady =>
      _controller != null && _controller!.value.isInitialized;

  @override
  Size? get previewSize {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return null;
    return c.value.previewSize;
  }

  @override
  Widget buildPreview({Widget? placeholder}) {
    final c = _controller;
    if (c == null || !c.value.isInitialized) {
      return placeholder ?? const SizedBox.shrink();
    }
    return CameraPreview(c);
  }

  @override
  Future<bool> initialize() async {
    if (isReady) return true;
    if (_initializing) return false;
    _initializing = true;

    try {
      final status = await Permission.camera.request();
      if (!status.isGranted) return false;

      final cameras = await availableCameras();
      if (cameras.isEmpty) return false;

      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      final controller = CameraController(
        back,
        
        
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await controller.initialize();
      _controller = controller;
      return true;
    } catch (_) {
      _controller = null;
      return false;
    } finally {
      _initializing = false;
    }
  }

  @override
  Future<Uint8List?> captureJpeg() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return null;
    if (controller.value.isTakingPicture) return null;

    try {
      final file = await controller.takePicture();
      return await file.readAsBytes();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> dispose() async {
    final controller = _controller;
    _controller = null;
    await controller?.dispose();
  }
}
