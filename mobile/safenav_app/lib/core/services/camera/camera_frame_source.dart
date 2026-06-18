import 'dart:typed_data';

import 'package:flutter/widgets.dart';

/// Captures camera frames as JPEG bytes for the obstacle-avoidance pipeline.
///
/// Implementations MUST return JPEGs that carry their EXIF orientation tag.
/// The detection server relies on EXIF to display frames upright; a JPEG with
/// no EXIF tag is rotated 90° server-side, which corrupts every detection.
abstract class CameraFrameSource {
  /// Whether the camera has been initialised and is ready to capture.
  bool get isReady;

  /// Native preview size (sensor orientation), or null when not ready.
  Size? get previewSize;

  /// Initialise the camera. Returns true on success. Safe to call more than
  /// once; subsequent calls are no-ops while already initialised.
  Future<bool> initialize();

  /// Capture a single frame encoded as JPEG (with EXIF orientation).
  /// Returns null if the camera is not ready or a capture is already running.
  Future<Uint8List?> captureJpeg();

  /// A live preview widget for the developer screen. Returns [placeholder]
  /// (or an empty box) when the camera is not yet ready.
  Widget buildPreview({Widget? placeholder});

  /// Release the camera hardware.
  Future<void> dispose();
}
