import 'package:flutter_test/flutter_test.dart';
import 'package:safenav_app/features/obstacle_avoidance/domain/entities/detection_result.dart';

void main() {
  group('DetectionResult.fromJson', () {
    test('parses instruction, obstacles, metrics and frame size', () {
      final json = {
        'frame_id': 12,
        'instruction': 'Obstacle ahead, move left',
        'obstacles': [
          {
            'label': 'person',
            'confidence': 0.91,
            'distance': 2.4,
            'bbox': [0.1, 0.2, 0.3, 0.4],
          },
          {
            'label': 'chair',
            'confidence': 0.55,
            'bbox': [0.5, 0.5, 0.6, 0.7],
          },
        ],
        'frame_size': {'w': 640, 'h': 480},
        'metrics': {
          'yolo_ms': 12.3,
          'depth_ms': 20.0,
          'sam_ms': 15.5,
          'total_ms': 60.2,
          'server_fps': 16.6,
          'frames_processed': 100,
        },
        'skipped': false,
        'depth_attached': false,
        'seg_attached': false,
        'yolo_attached': false,
        'mask_attached': false,
      };

      final r = DetectionResult.fromJson(json);
      expect(r.frameId, 12);
      expect(r.instruction, 'Obstacle ahead, move left');
      expect(r.obstacles.length, 2);
      expect(r.obstacles.first.label, 'person');
      expect(r.obstacles.first.confidence, closeTo(0.91, 1e-9));
      expect(r.obstacles.first.distanceMeters, closeTo(2.4, 1e-9));
      expect(r.obstacles[1].distanceMeters, isNull);
      expect(r.frameWidth, 640);
      expect(r.frameHeight, 480);
      expect(r.metrics.yoloMs, closeTo(12.3, 1e-9));
      expect(r.metrics.totalMs, closeTo(60.2, 1e-9));
      expect(r.expectedAttachments, 0);
    });

    test('reads distance from alternative keys', () {
      final r = DetectionResult.fromJson({
        'instruction': '',
        'obstacles': [
          {'label': 'car', 'confidence': 0.7, 'depth_m': 5.0, 'bbox': []},
        ],
      });
      expect(r.obstacles.single.distanceMeters, closeTo(5.0, 1e-9));
    });

    test('counts expected preview attachments from the *_attached flags', () {
      final r = DetectionResult.fromJson({
        'instruction': 'x',
        'depth_attached': true,
        'seg_attached': true,
        'yolo_attached': true,
        'mask_attached': false,
      });
      expect(r.expectedAttachments, 3);
    });

    test('tolerates a server error response with no instruction', () {
      final r = DetectionResult.fromJson({'error': 'Inference failure'});
      expect(r.hasInstruction, isFalse);
      expect(r.obstacles, isEmpty);
      expect(r.expectedAttachments, 0);
    });

    test('parses MAD from the top level', () {
      final r = DetectionResult.fromJson({'instruction': 'x', 'mad': 2.73});
      expect(r.mad, closeTo(2.73, 1e-9));
    });

    test('parses MAD nested in metrics', () {
      final r = DetectionResult.fromJson({
        'instruction': 'x',
        'metrics': {'mad': 1.5, 'yolo_ms': 10.0},
      });
      expect(r.mad, closeTo(1.5, 1e-9));
    });

    test('parses MAD from metrics.frame_signature_mad (server field)', () {
      final r = DetectionResult.fromJson({
        'instruction': 'x',
        'metrics': {'frame_signature_mad': 3.14, 'yolo_ms': 10.0},
      });
      expect(r.mad, closeTo(3.14, 1e-9));
    });

    test('skipped frame: fresh top-level sig_mad wins over stale metrics copy',
        () {
      // A skipped response is a copy of the last processed one (stale
      // metrics.frame_signature_mad) plus a fresh top-level sig_mad.
      final r = DetectionResult.fromJson({
        'frame_id': 9,
        'skipped': true,
        'sig_mad': 0.42,
        'metrics': {'frame_signature_mad': 7.7, 'yolo_ms': 10.0},
      });
      expect(r.skipped, isTrue);
      expect(r.mad, closeTo(0.42, 1e-9));
    });

    test('mad is null when not provided', () {
      final r = DetectionResult.fromJson({'instruction': 'x'});
      expect(r.mad, isNull);
    });

    test('exposes all scalar metrics for listing', () {
      final r = DetectionResult.fromJson({
        'instruction': 'x',
        'metrics': {
          'yolo_ms': 1.0,
          'nav_ms': 2.0,
          'server_fps': 30.0,
          'rolling': {'yolo_ms': 1.1}, // nested map ignored by scalarEntries
        },
      });
      final keys = r.metrics.scalarEntries.map((e) => e.key).toList();
      expect(keys, containsAll(<String>['yolo_ms', 'nav_ms', 'server_fps']));
      expect(keys, isNot(contains('rolling')));
    });
  });

  group('car proximity (vibration trigger)', () {
    test('hasCar true when the highest-priority obstacle is a car', () {
      final r = DetectionResult.fromJson({
        'instruction': 'path blocked',
        'highest_priority': {'label': 'car', 'bbox': [0.4, 0.3, 0.6, 0.8]},
        'free_zones': {
          'left': {'clear': true, 'clearance_m': 4.0},
          'slight_left': {'clear': true, 'clearance_m': 4.0},
          'centre': {'clear': false, 'clearance_m': 1.5},
          'slight_right': {'clear': true, 'clearance_m': 4.0},
          'right': {'clear': true, 'clearance_m': 4.0},
        },
      });
      expect(r.hasCar, isTrue);
      // Car centre x = 0.5 -> centre region (index 2) -> clearance 1.5 m.
      expect(r.carDistanceMeters(), closeTo(1.5, 1e-9));
    });

    test('uses the car obstacle distance when the server provides one', () {
      final r = DetectionResult.fromJson({
        'instruction': 'path blocked',
        'obstacles': [
          {'label': 'car', 'confidence': 0.9, 'distance': 1.2, 'bbox': []},
        ],
      });
      expect(r.hasCar, isTrue);
      expect(r.carDistanceMeters(), closeTo(1.2, 1e-9));
    });

    test('falls back to min blocked clearance when bbox is missing', () {
      final r = DetectionResult.fromJson({
        'instruction': 'path blocked',
        'highest_priority': {'label': 'car'},
        'free_zones': {
          'centre': {'clear': false, 'clearance_m': 1.0},
          'right': {'clear': true, 'clearance_m': 3.0},
        },
      });
      expect(r.carDistanceMeters(), closeTo(1.0, 1e-9));
    });

    test('no car -> hasCar false and distance null', () {
      final r = DetectionResult.fromJson({
        'instruction': 'path clear',
        'obstacles': [
          {'label': 'person', 'confidence': 0.8, 'bbox': [0.4, 0.3, 0.6, 0.8]},
        ],
      });
      expect(r.hasCar, isFalse);
      expect(r.carDistanceMeters(), isNull);
    });
  });

  group('parseFreeZones', () {
    test('parses a list of booleans in order', () {
      final z = parseFreeZones([true, false, true, true, false]);
      expect(z.map((e) => e.free).toList(), [true, false, true, true, false]);
    });

    test('parses a list of objects (free / blocked / status)', () {
      final z = parseFreeZones([
        {'free': true},
        {'blocked': true},
        {'status': 'clear'},
        {'occupied': false},
        {'is_free': false},
      ]);
      expect(z.map((e) => e.free).toList(), [true, false, true, true, false]);
    });

    test('parses a list of FREE indices over 5 regions', () {
      final z = parseFreeZones([0, 2, 4]);
      expect(z.length, 5);
      expect(z.map((e) => e.free).toList(),
          [true, false, true, false, true]);
    });

    test('parses the region-keyed map (server format) in left-to-right order',
        () {
      final z = parseFreeZones({
        'left': {'clear': false, 'clearance_m': 0.86},
        'slight_left': {'clear': true, 'clearance_m': 3.65},
        'centre': {'clear': true, 'clearance_m': 4.66},
        'slight_right': {'clear': true, 'clearance_m': 4.47},
        'right': {'clear': true, 'clearance_m': 3.87},
      });
      expect(z.length, 5);
      expect(z.map((e) => e.free).toList(),
          [false, true, true, true, true]);
      expect(z.map((e) => e.label).toList(),
          ['Left', 'Slight left', 'Centre', 'Slight right', 'Right']);
      expect(z[0].clearanceM, closeTo(0.86, 1e-9));
      expect(z[2].clearanceM, closeTo(4.66, 1e-9));
    });

    test('parses clearance_m per region', () {
      final z = parseFreeZones([
        {'free': true, 'clearance_m': 3.5},
        {'blocked': true, 'clearance_m': 0.4},
      ]);
      expect(z[0].free, isTrue);
      expect(z[0].clearanceM, closeTo(3.5, 1e-9));
      expect(z[1].free, isFalse);
      expect(z[1].clearanceM, closeTo(0.4, 1e-9));
    });

    test('empty / non-list yields no zones', () {
      expect(parseFreeZones(null), isEmpty);
      expect(parseFreeZones([]), isEmpty);
    });

    test('DetectionResult exposes parsed free zones', () {
      final r = DetectionResult.fromJson({
        'instruction': 'x',
        'free_zones': [true, false, true, false, true],
      });
      expect(r.freeZones.length, 5);
      expect(r.freeZones.first.free, isTrue);
    });
  });
}
