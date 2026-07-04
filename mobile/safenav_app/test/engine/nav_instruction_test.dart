import 'package:flutter_test/flutter_test.dart';
import 'package:safenav_app/features/mapbox_navigation/domain/engine/nav_instruction.dart';
import 'package:safenav_app/features/mapbox_navigation/domain/engine/route_path.dart'
    show TurnDirection;

void main() {
  group('NavPhrasing vocabulary', () {
    List<NavInstruction> allPossibleInstructions() => [
          NavPhrasing.continueStraight(30),
          NavPhrasing.continueStraight(1),
          NavPhrasing.continueStraight(0),
          NavPhrasing.continueStraight(123.6),
          NavPhrasing.continueStraight(45, isFinalLeg: true),
          NavPhrasing.turn(TurnDirection.left),
          NavPhrasing.turn(TurnDirection.right),
          NavPhrasing.turn(TurnDirection.straight),
          NavPhrasing.orientation(FacingCorrection.turnLeft),
          NavPhrasing.orientation(FacingCorrection.turnRight),
          NavPhrasing.orientation(FacingCorrection.turnAround),
          NavPhrasing.arrival(),
        ];

    test('NEVER contains "slight" or "sharp" (case-insensitive)', () {
      for (final inst in allPossibleInstructions()) {
        final lower = inst.text.toLowerCase();
        expect(lower.contains('slight'), isFalse, reason: inst.text);
        expect(lower.contains('sharp'), isFalse, reason: inst.text);
      }
    });

    test('"continue straight ahead" always includes a distance in meters', () {
      final re = RegExp(r'^Continue straight ahead for \d+ meters?');
      expect(re.hasMatch(NavPhrasing.continueStraight(30).text), isTrue);
      expect(re.hasMatch(NavPhrasing.continueStraight(123.6).text), isTrue);
      expect(NavPhrasing.continueStraight(1).text, contains('1 meter.'));
      expect(NavPhrasing.continueStraight(0).text, contains('1 meter'));
      expect(NavPhrasing.continueStraight(123.6).text, contains('124 meters'));
    });

    test('final leg phrases toward the destination', () {
      final inst = NavPhrasing.continueStraight(45, isFinalLeg: true);
      expect(inst.text, contains('to your destination'));
    });

    test('turn instructions carry NO distance and are critical', () {
      final left = NavPhrasing.turn(TurnDirection.left);
      final right = NavPhrasing.turn(TurnDirection.right);
      expect(left.text, 'Turn left.');
      expect(right.text, 'Turn right.');
      expect(left.text, isNot(matches(RegExp(r'\d'))));
      expect(right.text, isNot(matches(RegExp(r'\d'))));
      expect(left.isCritical, isTrue);
      expect(right.isCritical, isTrue);
    });

    test('orientation corrections use the allowed three phrasings', () {
      expect(NavPhrasing.orientation(FacingCorrection.turnLeft).text,
          'Turn left to face the path.');
      expect(NavPhrasing.orientation(FacingCorrection.turnRight).text,
          'Turn right to face the path.');
      expect(NavPhrasing.orientation(FacingCorrection.turnAround).text,
          'Turn around to face the path.');
      expect(NavPhrasing.orientation(FacingCorrection.turnLeft).isCritical,
          isFalse);
    });

    test('arrival announcement', () {
      final a = NavPhrasing.arrival();
      expect(a.kind, NavInstructionKind.arrival);
      expect(a.text.toLowerCase(), contains('arrived'));
      expect(a.isCritical, isTrue);
    });

    test('continue is non-critical', () {
      expect(NavPhrasing.continueStraight(10).isCritical, isFalse);
    });
  });
}
