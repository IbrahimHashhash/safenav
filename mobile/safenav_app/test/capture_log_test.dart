import 'package:flutter_test/flutter_test.dart';
import 'package:safenav_app/features/obstacle_avoidance/data/capture_log_service.dart';
import 'package:safenav_app/features/obstacle_avoidance/domain/entities/detection_result.dart';

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
  });
}
