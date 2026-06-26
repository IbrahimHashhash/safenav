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

  group('end-to-end: same obstacle, changing distance', () {
    test('chair at 3m then 2m is spoken once within the cooldown', () {
      final gate = SpeechRepeatGate(cooldown);
      final k1 = SpeechRepeatGate.keyFor(
          label: 'chair', region: 1, text: 'chair 3 meters ahead');
      final k2 = SpeechRepeatGate.keyFor(
          label: 'chair', region: 1, text: 'chair 2 meters ahead');
      expect(gate.allow(k1, t0), isTrue);
      expect(gate.allow(k2, t0.add(const Duration(seconds: 2))), isFalse);
    });
  });
}
