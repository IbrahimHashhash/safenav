import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import '../../../core/services/gallery/gallery_saver.dart';
import '../domain/entities/detection_result.dart';

/// Metadata returned after a capture is persisted.
class CaptureRecord {
  final int frameId;
  final String imagePath;
  final String csvPath;

  /// Number of model preview images saved alongside the frame.
  final int previewCount;

  /// Number of images (frame + previews) also saved to the device gallery.
  final int gallerySaved;

  const CaptureRecord({
    required this.frameId,
    required this.imagePath,
    required this.csvPath,
    this.previewCount = 0,
    this.gallerySaved = 0,
  });

  String get imageFileName => imagePath.split(Platform.pathSeparator).last;
}

/// CSV header for the capture log.
const String captureCsvHeader =
    'captured_at,frame_id,image_file,skipped,mad,end_to_end_ms,'
    'decode_ms,yolo_ms,depth_ms,sam_ms,stairs_ms,nav_ms,encode_ms,total_ms,'
    'server_fps,instruction,obstacle_count,obstacles';

String _num(num? v, [int? fractionDigits]) {
  if (v == null) return '';
  return fractionDigits != null ? v.toStringAsFixed(fractionDigits) : '$v';
}

String _csv(String s) {
  if (s.contains(',') || s.contains('"') || s.contains('\n')) {
    return '"${s.replaceAll('"', '""')}"';
  }
  return s;
}

/// Builds one CSV row from a [DetectionResult]. Pure (no IO) so it is unit
/// testable. Previews are intentionally NOT included.
String buildCaptureCsvRow(
  DetectionResult r,
  DateTime capturedAt,
  String imageFileName,
) {
  final m = r.metrics;
  final obstacles = r.obstacles
      .map((o) =>
          '${o.label}:${o.confidence.toStringAsFixed(2)}:'
          '${o.distanceMeters?.toStringAsFixed(1) ?? "?"}')
      .join(';');

  final fields = <String>[
    capturedAt.toIso8601String(),
    '${r.frameId}',
    imageFileName,
    '${r.skipped}',
    _num(r.mad, 2),
    _num(r.endToEndMs, 1),
    _num(m.decodeMs, 1),
    _num(m.yoloMs, 1),
    _num(m.depthMs, 1),
    _num(m.samMs, 1),
    _num(m.stairsMs, 1),
    _num(m.navMs, 1),
    _num(m.encodeMs, 1),
    _num(m.totalMs, 1),
    _num(m.serverFps, 2),
    _csv(r.instruction),
    '${r.obstacles.length}',
    _csv(obstacles),
  ];
  return fields.join(',');
}

/// Persists captured frames (the JPEG itself plus the model preview images,
/// when present) and their metrics to a CSV in the app documents directory,
/// for later inspection.
class CaptureLogService {
  CaptureLogService({this.gallery});

  /// Test seam: use a fixed directory instead of the platform documents dir.
  CaptureLogService.forDirectory(Directory dir, {this.gallery}) : _dir = dir;

  /// Optional gallery saver; when set, captures are also copied to the device
  /// gallery so they are viewable in the Photos app.
  final GallerySaver? gallery;

  Directory? _dir;

  Future<Directory> _ensureDir() async {
    if (_dir != null) return _dir!;
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/safenav_captures');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _dir = dir;
    return dir;
  }

  /// Absolute path of the captures directory (for showing the user).
  Future<String> directoryPath() async => (await _ensureDir()).path;

  /// Absolute path of the CSV log file.
  Future<String> csvPath() async => '${(await _ensureDir()).path}/captures.csv';

  /// Whether the CSV log exists yet (i.e. at least one capture was saved).
  Future<bool> csvExists() async => File(await csvPath()).exists();

  /// Saves the frame JPEG, any attached model previews, and appends a metrics
  /// row to `captures.csv`.
  Future<CaptureRecord> save({
    required Uint8List frameJpeg,
    required DetectionResult result,
    required DateTime capturedAt,
  }) async {
    final dir = await _ensureDir();

    final stamp = capturedAt
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    final base = 'frame_${result.frameId}_$stamp';
    final imageName = '$base.jpg';
    final imageFile = File('${dir.path}/$imageName');
    await imageFile.writeAsBytes(frameJpeg, flush: true);

    var gallerySaved = 0;
    Future<void> toGallery(String name, Uint8List bytes) async {
      if (gallery == null) return;
      try {
        await gallery!.saveImage(bytes, name: name);
        gallerySaved++;
      } catch (_) {
        // Gallery save is best-effort; the local file copy already succeeded.
      }
    }

    await toGallery(base, frameJpeg);

    // Save whatever model previews came back with this frame.
    var previewCount = 0;
    Future<void> writePreview(String suffix, Uint8List? bytes, String ext) async {
      if (bytes == null || bytes.isEmpty) return;
      await File('${dir.path}/${base}_$suffix.$ext')
          .writeAsBytes(bytes, flush: true);
      previewCount++;
      await toGallery('${base}_$suffix', bytes);
    }

    await writePreview('yolo', result.yoloPreview, 'jpg');
    await writePreview('depth', result.depthPreview, 'jpg');
    await writePreview('seg', result.segPreview, 'jpg');
    await writePreview('mask', result.maskPreview, 'png');

    final csv = File('${dir.path}/captures.csv');
    if (!await csv.exists()) {
      await csv.writeAsString('$captureCsvHeader\n');
    }
    await csv.writeAsString(
      '${buildCaptureCsvRow(result, capturedAt, imageName)}\n',
      mode: FileMode.append,
    );

    return CaptureRecord(
      frameId: result.frameId,
      imagePath: imageFile.path,
      csvPath: csv.path,
      previewCount: previewCount,
      gallerySaved: gallerySaved,
    );
  }
}
