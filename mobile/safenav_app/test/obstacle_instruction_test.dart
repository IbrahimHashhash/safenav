import 'package:flutter_test/flutter_test.dart';
import 'package:safenav_app/features/obstacle_avoidance/domain/entities/obstacle_instruction.dart';

void main() {
  group('ObstacleInstruction.fromJson', () {
    test('reads ONLY the instruction field from a rich server response', () {
      final response = {
        'frame_id': 42,
        'instruction': 'Obstacle ahead, move left',
        'highest_priority': {'label': 'person'},
        'obstacles': [
          {'label': 'person', 'bbox': [0.1, 0.2, 0.3, 0.4]},
        ],
        'free_zones': [],
        'metrics': {'total_ms': 80.0},
        'device': 'cuda',
      };

      final instruction = ObstacleInstruction.fromJson(response);
      expect(instruction.message, 'Obstacle ahead, move left');
      expect(instruction.isEmpty, isFalse);
    });

    test('trims whitespace around the instruction', () {
      final instruction =
          ObstacleInstruction.fromJson({'instruction': '  turn now  '});
      expect(instruction.message, 'turn now');
    });

    test('is empty when instruction is missing (e.g. server error response)',
        () {
      final instruction =
          ObstacleInstruction.fromJson({'error': 'Inference failure'});
      expect(instruction.isEmpty, isTrue);
    });

    test('is empty when instruction is null or non-string', () {
      expect(ObstacleInstruction.fromJson({'instruction': null}).isEmpty,
          isTrue);
      expect(ObstacleInstruction.fromJson({'instruction': 123}).isEmpty,
          isTrue);
    });

    test('is empty for a skipped-frame response with no instruction', () {
      final instruction = ObstacleInstruction.fromJson({
        'frame_id': 7,
        'skipped': true,
      });
      expect(instruction.isEmpty, isTrue);
    });
  });
}
