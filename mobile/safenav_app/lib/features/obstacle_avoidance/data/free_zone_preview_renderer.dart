import 'dart:typed_data';
import 'dart:ui' as ui;

import '../domain/entities/detection_result.dart';

/// Renders the server's free-zone analysis into a standalone preview image so
/// it can be saved alongside the model previews (the server doesn't return a
/// free-zone image; the app draws it from the JSON).
///
/// Abstracted so the persistence layer stays unit-testable (a fake can be
/// injected in tests; the `dart:ui` implementation needs the engine).
abstract class FreeZonePreviewRenderer {
  /// Returns PNG bytes visualising [zones] (green = free, red = blocked) over
  /// the optional [background] frame JPEG, or null when nothing can be drawn.
  Future<Uint8List?> render({
    required List<FreeZone> zones,
    Uint8List? background,
  });
}

/// [FreeZonePreviewRenderer] backed by `dart:ui` (no widget tree required).
class UiFreeZonePreviewRenderer implements FreeZonePreviewRenderer {
  const UiFreeZonePreviewRenderer({this.width = 640, this.height = 480});

  final int width;
  final int height;

  @override
  Future<Uint8List?> render({
    required List<FreeZone> zones,
    Uint8List? background,
  }) async {
    if (zones.isEmpty) return null;

    final w = width.toDouble();
    final h = height.toDouble();
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(
      recorder,
      ui.Rect.fromLTWH(0, 0, w, h),
    );

    // Background: the captured frame if we can decode it, else dark grey.
    final bg = await _tryDecode(background);
    if (bg != null) {
      canvas.drawImageRect(
        bg,
        ui.Rect.fromLTWH(0, 0, bg.width.toDouble(), bg.height.toDouble()),
        ui.Rect.fromLTWH(0, 0, w, h),
        ui.Paint(),
      );
      bg.dispose();
    } else {
      canvas.drawRect(
        ui.Rect.fromLTWH(0, 0, w, h),
        ui.Paint()..color = const ui.Color(0xFF202020),
      );
    }

    // Analysis band: regions cover most of the height, leaving the foreground
    // at the bottom uncovered (matching the dev-screen overlay).
    final bandTop = h * 0.10;
    final bandHeight = h * 0.62;
    final cellWidth = w / zones.length;

    for (var i = 0; i < zones.length; i++) {
      final zone = zones[i];
      final left = i * cellWidth;
      final color = zone.free
          ? const ui.Color(0x5400C853) // green @ ~33%
          : const ui.Color(0x54FF1744); // red @ ~33%

      canvas.drawRect(
        ui.Rect.fromLTWH(left, bandTop, cellWidth, bandHeight),
        ui.Paint()..color = color,
      );
      // Divider between regions.
      if (i > 0) {
        canvas.drawRect(
          ui.Rect.fromLTWH(left - 1, bandTop, 2, bandHeight),
          ui.Paint()..color = const ui.Color(0x73FFFFFF),
        );
      }

      final clearance =
          zone.clearanceM != null ? '${zone.clearanceM!.toStringAsFixed(1)}m' : '';
      final label = '${zone.label ?? 'R${i + 1}'}\n'
          '${zone.free ? 'clear' : 'blocked'}'
          '${clearance.isNotEmpty ? '\n$clearance' : ''}';
      _drawLabel(canvas, label, left, bandTop + bandHeight - 46, cellWidth);
    }

    final picture = recorder.endRecording();
    final image = await picture.toImage(width, height);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    picture.dispose();
    return data?.buffer.asUint8List();
  }

  Future<ui.Image?> _tryDecode(Uint8List? bytes) async {
    if (bytes == null || bytes.isEmpty) return null;
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      return frame.image;
    } catch (_) {
      return null;
    }
  }

  void _drawLabel(
    ui.Canvas canvas,
    String text,
    double left,
    double top,
    double cellWidth,
  ) {
    final builder = ui.ParagraphBuilder(ui.ParagraphStyle(
      textAlign: ui.TextAlign.center,
      fontSize: 12,
      fontWeight: ui.FontWeight.w700,
      maxLines: 3,
    ))
      ..pushStyle(ui.TextStyle(
        color: const ui.Color(0xFFFFFFFF),
        shadows: const [
          ui.Shadow(color: ui.Color(0xFF000000), blurRadius: 2),
        ],
      ))
      ..addText(text);
    final paragraph = builder.build()
      ..layout(ui.ParagraphConstraints(width: cellWidth));
    canvas.drawParagraph(paragraph, ui.Offset(left, top));
  }
}
