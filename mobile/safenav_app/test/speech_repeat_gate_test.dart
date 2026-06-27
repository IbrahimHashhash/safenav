import 'package:flutter_test/flutter_test.dart';
import 'package:safenav_app/features/obstacle_avoidance/application/speech_repeat_gate.dart';

void main() {
  final t0 = DateTime(2026, 1, 1, 12, 0, 0);
  const cooldown = Duration(seconds: 10);

  group('SpeechRepeatGate.keyFor', () {
    test('same obstacle at different distances -> same key', () {
      final a = SpeechRepeatGate.keyFor(
          label: 'chair', region: 2, text: 'chair 3 meters ahead');
      final b = SpeechRepeatGate.keyFor(
          label: 'chair', region: 2, text: 'chair 2 meters ahead');
      expect(a, b);
    });

    test('different obstacle types -> different keys (car != chair)', () {
      final car = SpeechRepeatGate.keyFor(
          label: 'car', region: 2, text: 'car 3 meters ahead');
      final chair = SpeechRepeatGate.keyFor(
          label: 'chair', region: 2, text: 'chair 3 meters ahead');
      expect(car, isNot(chair));
    });

    test('same obstacle in a different region -> different key', () {
      final left = SpeechRepeatGate.keyFor(label: 'chair', region: 0, text: 'x');
      final right =
          SpeechRepeatGate.keyFor(label: 'chair', region: 4, text: 'x');
      expect(left, isNot(right));
    });

    test('no obstacle -> normalized text key', () {
      final a = SpeechRepeatGate.keyFor(label: null, text: 'Path is clear.');
      final b = SpeechRepeatGate.keyFor(label: '', text: 'path is clear');
      expect(a, b);
      expect(a, isNot(SpeechRepeatGate.keyFor(label: null, text: 'path likely blocked')));
    });
  });

  group('SpeechRepeatGate.allow', () {
    test('first is allowed; repeat within cooldown is dropped', () {
      final gate = SpeechRepeatGate(cooldown);
      const key = 'obstacle|chair|2';
      expect(gate.allow(key, t0), isTrue);
      expect(gate.allow(key, t0.add(const Duration(seconds: 3))), isFalse);
    });

    test('allowed again after cooldown elapses', () {
      final gate = SpeechRepeatGate(cooldown);
      const key = 'obstacle|chair|2';
      expect(gate.allow(key, t0), isTrue);
      expect(gate.allow(key, t0.add(const Duration(seconds: 11))), isTrue);
    });

    test('flicker does not defeat the cooldown', () {
      // chair -> car -> chair: the repeated chair is still suppressed.
      final gate = SpeechRepeatGate(cooldown);
      expect(gate.allow('obstacle|chair|2', t0), isTrue);
      expect(gate.allow('obstacle|car|2', t0.add(const Duration(seconds: 1))),
          isTrue);
      expect(gate.allow('obstacle|chair|2', t0.add(const Duration(seconds: 2))),
          isFalse);
    });

    test('different obstacle is allowed immediately', () {
      final gate = SpeechRepeatGate(cooldown);
      expect(gate.allow('obstacle|chair|2', t0), isTrue);
      expect(gate.allow('obstacle|car|2', t0.add(const Duration(seconds: 1))),
          isTrue);
    });

    test('reset clears history', () {
      final gate = SpeechRepeatGate(cooldown);
      expect(gate.allow('obstacle|chair|2', t0), isTrue);
      gate.reset();
      expect(gate.allow('obstacle|chair|2', t0.add(const Duration(seconds: 1))),
          isTrue);
    });
  });

  group('SpeechRepeatGate.allow with distance', () {
    const key = 'obstacle|car|2';

    test('large distance change within cooldown is allowed (10 m -> 5 m)', () {
      final gate = SpeechRepeatGate(cooldown);
      expect(gate.allow(key, t0, distance: 10, distanceThreshold: 0.5), isTrue);
      expect(
        gate.allow(key, t0.add(const Duration(seconds: 2)),
            distance: 5, distanceThreshold: 0.5),
        isTrue,
      );
    });

    test('small distance change within cooldown is suppressed (3.0 -> 2.8)', () {
      final gate = SpeechRepeatGate(cooldown);
      expect(
          gate.allow(key, t0, distance: 3.0, distanceThreshold: 0.5), isTrue);
      expect(
        gate.allow(key, t0.add(const Duration(seconds: 2)),
            distance: 2.8, distanceThreshold: 0.5),
        isFalse,
      );
    });

    test('a change of exactly the threshold is suppressed (0.5 m)', () {
      final gate = SpeechRepeatGate(cooldown);
      expect(
          gate.allow(key, t0, distance: 3.0, distanceThreshold: 0.5), isTrue);
      expect(
        gate.allow(key, t0.add(const Duration(seconds: 1)),
            distance: 2.5, distanceThreshold: 0.5),
        isFalse,
      );
    });

    test('a change just over the threshold is allowed (> 0.5 m)', () {
      final gate = SpeechRepeatGate(cooldown);
      expect(
          gate.allow(key, t0, distance: 3.0, distanceThreshold: 0.5), isTrue);
      expect(
        gate.allow(key, t0.add(const Duration(seconds: 1)),
            distance: 2.49, distanceThreshold: 0.5),
        isTrue,
      );
    });

    test('a meaningful change is measured from the LAST announced distance', () {
      final gate = SpeechRepeatGate(cooldown);
      // 5.0 announced; 4.7 (-0.3) suppressed; 4.4 is only -0.3 from 4.7 but
      // -0.6 from the last *announced* 5.0 -> allowed.
      expect(
          gate.allow(key, t0, distance: 5.0, distanceThreshold: 0.5), isTrue);
      expect(
        gate.allow(key, t0.add(const Duration(seconds: 1)),
            distance: 4.7, distanceThreshold: 0.5),
        isFalse,
      );
      expect(
        gate.allow(key, t0.add(const Duration(seconds: 2)),
            distance: 4.4, distanceThreshold: 0.5),
        isTrue,
      );
    });

    test('no threshold keeps pure time-based suppression', () {
      final gate = SpeechRepeatGate(cooldown);
      expect(gate.allow(key, t0, distance: 10), isTrue);
      expect(
        gate.allow(key, t0.add(const Duration(seconds: 2)), distance: 1),
        isFalse,
      );
    });
  });

  group('end-to-end: same obstacle, changing distance', () {
    final k1 = SpeechRepeatGate.keyFor(
        label: 'chair', region: 1, text: 'chair 3 meters ahead');
    final k2 = SpeechRepeatGate.keyFor(
        label: 'chair', region: 1, text: 'chair 2 meters ahead');

    test('keys collapse regardless of distance (distance excluded from key)',
        () {
      expect(k1, k2);
    });

    test('chair 3 m -> 2 m (>= 0.5 m) is re-announced within the cooldown', () {
      final gate = SpeechRepeatGate(cooldown);
      expect(
          gate.allow(k1, t0, distance: 3.0, distanceThreshold: 0.5), isTrue);
      expect(
        gate.allow(k2, t0.add(const Duration(seconds: 2)),
            distance: 2.0, distanceThreshold: 0.5),
        isTrue,
      );
    });

    test('chair 3.0 m -> 2.8 m (< 0.5 m) stays suppressed', () {
      final gate = SpeechRepeatGate(cooldown);
      expect(
          gate.allow(k1, t0, distance: 3.0, distanceThreshold: 0.5), isTrue);
      expect(
        gate.allow(k1, t0.add(const Duration(seconds: 2)),
            distance: 2.8, distanceThreshold: 0.5),
        isFalse,
      );
    });
  });
}
