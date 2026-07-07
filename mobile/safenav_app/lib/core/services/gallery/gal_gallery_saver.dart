import 'dart:typed_data';

import 'package:gal/gal.dart';

import 'gallery_saver.dart';



class GalGallerySaver implements GallerySaver {
  static const String _album = 'SafeNav';

  @override
  Future<void> saveImage(Uint8List bytes, {required String name}) async {
    if (!await Gal.hasAccess(toAlbum: true)) {
      await Gal.requestAccess(toAlbum: true);
    }
    try {
      await Gal.putImageBytes(bytes, album: _album, name: name);
    } on GalException {
      
      await Gal.putImageBytes(bytes, name: name);
    }
  }
}
