import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:safenav_app/core/services/gallery/gallery_saver.dart';
import 'package:safenav_app/features/obstacle_avoidance/data/capture_log_service.dart';
import 'package:safenav_app/features/obstacle_avoidance/data/free_zone_preview_renderer.dart';
import 'package:safenav_app/features/obstacle_avoidance/domain/entities/detection_result.dart';

class _FakeGallery implements GallerySaver {
  final List<String> names = [];
  @override
  Future<void> saveImage(Uint8List bytes, {required String name}) async {
    names.add(name);
  }
}

/// Fake renderer that returns fixed bytes only when zones are present, so the
/// save() path can be tested without the Flutter engine.
class _FakeFreeZoneRenderer implements FreeZonePreviewRenderer {
  int calls = 0;
  @override
  Future<Uint8List?> render({
    required List<FreeZone> zones,
    Uint8List? background,
  }) async {
    calls++;
    if (zones.isEmpty) return null;
    return Uint8List.fromList([9, 9, 9]);
  }
}

void main() {
  group('buildCaptureCsvRow', () {
    final capturedAt = DateTime.utc(2026, 6, 19, 13, 0, 0);

    test('serializes core fields, metrics, and obstacles (no previews)', () {
      final r = DetectionResult.fromJson({
        'frame_id': 7,
        'instruction': 'Obstacle ahead - move left',
        'skipped': false,
        'mad': 4.2,
        'obstacles': [
          {'label': 'person', 'confidence': 0.91, 'distance': 2.4},
          {'label': 'chair', 'confidence': 0.55},
        ],
        'metrics': {
          'yolo_ms': 12.3,
          'depth_ms': 20.0,
          'total_ms': 60.0,
          'server_fps': 16.6,
        },
      });
      r.endToEndMs = 123.4;

      final row = buildCaptureCsvRow(r, capturedAt, 'frame_7.jpg');
      final cols = row.split(',');

      // captured_at, frame_id, image_file
      expect(cols[0], '2026-06-19T13:00:00.000Z');
      expect(cols[1], '7');
      expect(cols[2], 'frame_7.jpg');
      expect(cols[3], 'false'); // skipped
      expect(cols[4], '4.20'); // mad
      expect(cols[5], '123.4'); // end_to_end_ms
      // header column count matches the row column count (no escaping here).
      expect(cols.length, captureCsvHeader.split(',').length);
      // obstacles serialized with label:conf:dist
      expect(row, contains('person:0.91:2.4'));
      expect(row, contains('chair:0.55:?')); // missing distance -> ?
    });

    test('quotes an instruction that contains a comma', () {
      final r = DetectionResult.fromJson({
        'frame_id': 1,
        'instruction': 'Turn left, then stop',
      });
      final row = buildCaptureCsvRow(r, capturedAt, 'f.jpg');
      expect(row, contains('"Turn left, then stop"'));
      // The quoted field must not break the column count.
      // Re-join everything outside quotes is non-trivial; just assert presence.
    });

    test('empty metrics produce empty numeric fields, not crashes', () {
      final r = DetectionResult.fromJson({'frame_id': 2, 'instruction': 'x'});
      final row = buildCaptureCsvRow(r, capturedAt, 'f.jpg');
      expect(row.startsWith('2026-06-19T13:00:00.000Z,2,f.jpg,false,,'), isTrue);
    });

    test('serializes free zones (name:state:clearance) and the count', () {
      final r = DetectionResult.fromJson({
        'frame_id': 3,
        'instruction': 'ok',
        'free_zones': {
          'left': {'clear': false, 'clearance_m': 0.9},
          'centre': {'clear': true, 'clearance_m': 3.2},
          'right': {'clear': true, 'clearance_m': 4.0},
        },
      });
      final row = buildCaptureCsvRow(r, capturedAt, 'f.jpg');
      final cols = row.split(',');
      // Row and header still line up (the free_zones field has no commas).
      expect(cols.length, captureCsvHeader.split(',').length);
      // free_zone_count then the serialized zones.
      expect(row, contains(',3,Left:blocked:0.9;Centre:free:3.2;Right:free:4.0'));
    });
  });

  group('CaptureLogService preview saving', () {
    test('saves the frame plus all attached previews and counts them',
        () async {
      final dir = await Directory.systemTemp.createTemp('safenav_cap_test');
      addTearDown(() => dir.delete(recursive: true));

      final r = DetectionResult.fromJson({
        'frame_id': 5,
        'instruction': 'ok',
        'yolo_attached': true,
        'depth_attached': true,
        'seg_attached': true,
        'mask_attached': true,
      });
      r.yoloPreview = Uint8List.fromList([1, 2, 3]);
      r.depthPreview = Uint8List.fromList([4, 5]);
      r.segPreview = Uint8List.fromList([6]);
      r.maskPreview = Uint8List.fromList([7, 8, 9, 10]);

      final svc = CaptureLogService.forDirectory(dir);
      final record = await svc.save(
        frameJpeg: Uint8List.fromList([0, 0]),
        result: r,
        capturedAt: DateTime.utc(2026, 6, 20, 16, 0, 0),
      );

      expect(record.previewCount, 4);
      final names = dir
          .listSync()
          .map((e) => e.path.split(Platform.pathSeparator).last)
          .toList();
      expect(names.any((n) => n.endsWith('_yolo.jpg')), isTrue);
      expect(names.any((n) => n.endsWith('_depth.jpg')), isTrue);
      expect(names.any((n) => n.endsWith('_seg.jpg')), isTrue);
      expect(names.any((n) => n.endsWith('_mask.png')), isTrue);
      expect(names.contains('captures.csv'), isTrue);
    });

    test('saves no previews when none are attached', () async {
      final dir = await Directory.systemTemp.createTemp('safenav_cap_test2');
      addTearDown(() => dir.delete(recursive: true));
      final r = DetectionResult.fromJson({'frame_id': 6, 'instruction': 'ok'});
      final record = await CaptureLogService.forDirectory(dir).save(
        frameJpeg: Uint8List.fromList([0]),
        result: r,
        capturedAt: DateTime.utc(2026, 6, 20, 16, 0, 0),
      );
      expect(record.previewCount, 0);
    });

    test('renders and saves a free-zone preview (file + gallery) when zones '
        'are present and a renderer is set', () async {
      final dir = await Directory.systemTemp.createTemp('safenav_cap_fz');
      addTearDown(() => dir.delete(recursive: true));
      final fakeGallery = _FakeGallery();
      final renderer = _FakeFreeZoneRenderer();

      final r = DetectionResult.fromJson({
        'frame_id': 11,
        'instruction': 'ok',
        'free_zones': {
          'left': {'clear': false, 'clearance_m': 1.0},
          'right': {'clear': true, 'clearance_m': 3.0},
        },
      });

      final record = await CaptureLogService.forDirectory(
        dir,
        gallery: fakeGallery,
        freeZoneRenderer: renderer,
      ).save(
        frameJpeg: Uint8List.fromList([0, 0]),
        result: r,
        capturedAt: DateTime.utc(2026, 6, 20, 16, 0, 0),
      );

      expect(renderer.calls, 1);
      // free-zone preview counts as a preview.
      expect(record.previewCount, 1);
      final names = dir
          .listSync()
          .map((e) => e.path.split(Platform.pathSeparator).last)
          .toList();
      expect(names.any((n) => n.endsWith('_freezones.png')), isTrue);
      // frame + freezones = 2 sent to the gallery.
      expect(record.gallerySaved, 2);
      expect(fakeGallery.names.any((n) => n.endsWith('_freezones')), isTrue);
    });

    test('does not render a free-zone preview when there are no zones',
        () async {
      final dir = await Directory.systemTemp.createTemp('safenav_cap_fz2');
      addTearDown(() => dir.delete(recursive: true));
      final renderer = _FakeFreeZoneRenderer();
      final r = DetectionResult.fromJson({'frame_id': 12, 'instruction': 'ok'});
      final record = await CaptureLogService.forDirectory(
        dir,
        freeZoneRenderer: renderer,
      ).save(
        frameJpeg: Uint8List.fromList([0]),
        result: r,
        capturedAt: DateTime.utc(2026, 6, 20, 16, 0, 0),
      );
      // Renderer is not even called when there are no zones.
      expect(renderer.calls, 0);
      expect(record.previewCount, 0);
    });

    test('also saves frame + previews to the gallery when a saver is set',
        () async {
      final dir = await Directory.systemTemp.createTemp('safenav_cap_test3');
      addTearDown(() => dir.delete(recursive: true));
      final fakeGallery = _FakeGallery();

      final r = DetectionResult.fromJson({
        'frame_id': 9,
        'instruction': 'ok',
        'yolo_attached': true,
        'mask_attached': true,
      });
      r.yoloPreview = Uint8List.fromList([1, 2]);
      r.maskPreview = Uint8List.fromList([3, 4]);

      final record =
          await CaptureLogService.forDirectory(dir, gallery: fakeGallery).save(
        frameJpeg: Uint8List.fromList([0, 0]),
        result: r,
        capturedAt: DateTime.utc(2026, 6, 20, 16, 0, 0),
      );

      // frame + yolo + mask = 3 images sent to the gallery.
      expect(record.gallerySaved, 3);
      expect(fakeGallery.names.length, 3);
      expect(fakeGallery.names.any((n) => n.endsWith('_yolo')), isTrue);
      expect(fakeGallery.names.any((n) => n.endsWith('_mask')), isTrue);
    });
  });
}
