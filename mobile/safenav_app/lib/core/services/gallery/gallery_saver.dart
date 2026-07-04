import 'dart:typed_data';




abstract class GallerySaver {
  
  
  Future<void> saveImage(Uint8List bytes, {required String name});
}
