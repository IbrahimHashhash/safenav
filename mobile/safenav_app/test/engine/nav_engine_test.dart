import 'package:flutter_test/flutter_test.dart';
import 'package:safenav_app/features/mapbox_navigation/domain/engine/geo_point.dart';
import 'package:safenav_app/features/mapbox_navigation/domain/engine/nav_engine.dart';
import 'package:safenav_app/features/mapbox_navigation/domain/engine/nav_instruction.dart';
import 'package:safenav_app/features/mapbox_navigation/domain/engine/route_path.dart';

void main() {
  // A -> B due east, B -> C due north  => LEFT turn at B.
  const a = GeoPoint(31.9600, 35.1800);
  const b = GeoPoint(31.9600, 35.1820);
  const c = GeoPoint(31.9620, 35.1820);

  RoutePath lRoute() =>
      RoutePath.build(polyline: const [a, b, c], maneuverNodes: const [b]);

  const eastEnd = GeoPoint(31.9600, 35.1860);
  RoutePath straightRoute() => RoutePath.build(polyline: const [a, eastEnd]);

  final t0 = DateTime(2026, 1, 1, 12, 0, 0);

  group('continue / turn / arrival progression', () {
    test('emits "continue straight ahead" with distance at the start', () {
      final engine = NavEngine(lRoute());
      final u = engine.update(position: a, now: t0);
      expect(u.instruction, isNotNull);
      expect(u.instruction!.kind, NavInstructionKind.continueStraight);
      expect(u.instruction!.text, matches(RegExp(r'\d+ meters')));
      expect(u.instruction!.text, isNot(contains('destination')));
      expect(u.distanceToNext, greaterThan(100));
    });

    test('fires "turn left" when the turn anchor is reached, advances step', () {
      final engine = NavEngine(lRoute());
      engine.update(position: a, now: t0);
      final u =
          engine.update(position: b, now: t0.add(const Duration(seconds: 6)));
      expect(u.instruction, isNotNull);
      expect(u.instruction!.kind, NavInstructionKind.turn);
      expect(u.instruction!.text, 'Turn left.');
      expect(engine.nextTurnIndex, 1);
    });

    test('final leg continue is phrased toward the destination', () {
      final engine = NavEngine(lRoute());
      engine.update(position: a, now: t0);
      engine.update(position: b, now: t0.add(const Duration(seconds: 6)));
      const midBC = GeoPoint(31.9610, 35.1820);
      final u = engine.update(
          position: midBC, now: t0.add(const Duration(seconds: 12)));
      expect(u.instruction, isNotNull);
      expect(u.instruction!.kind, NavInstructionKind.continueStraight);
      expect(u.instruction!.text, contains('to your destination'));
    });

    test('announces arrival within the arrival radius', () {
      final engine = NavEngine(lRoute());
      engine.update(position: a, now: t0);
      final u =
          engine.update(position: c, now: t0.add(const Duration(seconds: 30)));
      expect(u.arrived, isTrue);
      expect(u.instruction!.kind, NavInstructionKind.arrival);
      final after =
          engine.update(position: c, now: t0.add(const Duration(seconds: 35)));
      expect(after.instruction, isNull);
      expect(after.arrived, isTrue);
    });
  });

  group('robust turn progression (never strands)', () {
    test('passing a maneuver advances the step even if never reached precisely',
        () {
      final engine = NavEngine(lRoute());
      engine.update(position: a, now: t0);
      const pastB = GeoPoint(31.9608, 35.1820);
      final u = engine.update(
          position: pastB, now: t0.add(const Duration(seconds: 6)));
      expect(engine.nextTurnIndex, 1);
      expect(u.instruction!.kind, NavInstructionKind.turn);
    });
  });

  group('cooldown & de-duplication', () {
    test('non-critical speech is gated by the cooldown', () {
      final engine = NavEngine(lRoute());
      final first = engine.update(position: a, now: t0);
      expect(first.instruction, isNotNull);
      const along = GeoPoint(31.9600, 35.180106);
      final second = engine.update(
          position: along, now: t0.add(const Duration(seconds: 1)));
      expect(second.instruction, isNull);
      final third = engine.update(
          position: along, now: t0.add(const Duration(seconds: 6)));
      expect(third.instruction, isNotNull);
    });

    test('identical consecutive lines are de-duplicated', () {
      final engine = NavEngine(
        lRoute(),
        config: const NavEngineConfig(speechCooldown: Duration.zero),
      );
      final first = engine.update(position: a, now: t0);
      expect(first.instruction, isNotNull);
      final second =
          engine.update(position: a, now: t0.add(const Duration(seconds: 1)));
      expect(second.instruction, isNull);
    });

    test('critical turn bypasses the cooldown', () {
      final engine = NavEngine(lRoute());
      engine.update(position: a, now: t0);
      final u =
          engine.update(position: b, now: t0.add(const Duration(seconds: 1)));
      expect(u.instruction, isNotNull);
      expect(u.instruction!.kind, NavInstructionKind.turn);
    });
  });

  group('path-relative orientation corrections', () {
    test('fires "turn left to face the path" when facing the wrong way', () {
      final engine = NavEngine(straightRoute());
      final u = engine.update(
          position: a, heading: 180, headingStable: true, now: t0);
      expect(u.instruction!.kind, NavInstructionKind.orientation);
      expect(u.instruction!.text, 'Turn left to face the path.');
    });

    test('fires "turn around" when facing roughly opposite', () {
      final engine = NavEngine(straightRoute());
      final u = engine.update(
          position: a, heading: 280, headingStable: true, now: t0);
      expect(u.instruction!.kind, NavInstructionKind.orientation);
      expect(u.instruction!.text, 'Turn around to face the path.');
    });

    test('suppressed inside the deadzone (aligned with path)', () {
      final engine = NavEngine(straightRoute());
      final u = engine.update(
          position: a, heading: 80, headingStable: true, now: t0);
      expect(u.instruction!.kind, NavInstructionKind.continueStraight);
    });

    test('never corrects on an unstable heading', () {
      final engine = NavEngine(straightRoute());
      final u = engine.update(
          position: a, heading: 180, headingStable: false, now: t0);
      expect(u.instruction!.kind, isNot(NavInstructionKind.orientation));
    });
  });
}
