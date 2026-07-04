import 'dart:typed_data';

/// Saves image bytes to the device's photo gallery so the user can view
/// captured frames/previews outside the app. Abstracted so the persistence
/// layer stays unit-testable (a no-op/fake can be injected in tests).
abstract class GallerySaver {
  /// Saves [bytes] to the gallery under [name]. Implementations should not
  /// throw on failure in a way that breaks the local file save.
  Future<void> saveImage(Uint8List bytes, {required String name});
}
