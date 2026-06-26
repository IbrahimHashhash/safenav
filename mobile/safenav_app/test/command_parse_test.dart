import 'package:flutter_test/flutter_test.dart';
import 'package:safenav_app/core/utils/text_utils.dart';
import 'package:safenav_app/features/voice_interaction/domain/entities/voice_command.dart';
import 'package:safenav_app/features/voice_interaction/domain/usecases/parse_intent_usecase.dart';

void main() {
  final parse = ParseIntentUseCase();

  group('false positives are rejected', () {
    test('"what the hell" is not a command', () {
      final intent = parse('what the hell');
      expect(intent, isNot(VoiceCommandType.listLocations));
      expect(intent, isNot(VoiceCommandType.moreInfo));
      expect(intent, VoiceCommandType.unknown);
    });

    test('short look-alikes do not trigger commands', () {
      // "hell" must not match "help"; "in" must not match "on", etc.
      expect(parse('what the hell'), VoiceCommandType.unknown);
      expect(parse('random gibberish words'), VoiceCommandType.unknown);
    });
  });

  group('exact fixed commands still work', () {
    test('detection toggles', () {
      expect(parse('start detection'), VoiceCommandType.startDetection);
      expect(parse('stop detection'), VoiceCommandType.stopDetection);
      expect(parse('begin obstacle detection'),
          VoiceCommandType.startDetection);
      expect(parse('turn off detection'), VoiceCommandType.stopDetection);
    });

    test('navigation toggles are not mistaken for detection', () {
      expect(parse('start navigation'), VoiceCommandType.startNavigation);
      expect(parse('stop navigation'), VoiceCommandType.stopNavigation);
    });

    test('list locations via content words', () {
      expect(parse('list locations'), VoiceCommandType.listLocations);
      expect(parse('show me the locations'), VoiceCommandType.listLocations);
      expect(parse('what places are there'), VoiceCommandType.listLocations);
    });
  });

  group('near-misses are rescued when unambiguous', () {
    test('"stop detension" -> stop detection', () {
      expect(parse('stop detension'), VoiceCommandType.stopDetection);
    });

    test('"start detension" -> start detection', () {
      expect(parse('start detension'), VoiceCommandType.startDetection);
    });
  });

  group('ambiguous input is not force-matched', () {
    test('"start addition" is treated as unknown, not a wrong command', () {
      // "addition" is roughly equidistant to "detection" and "navigation",
      // so the parser must NOT confidently fire either; it asks again.
      final intent = parse('start addition');
      expect(intent, isNot(VoiceCommandType.startNavigation));
      expect(intent, VoiceCommandType.unknown);
    });
  });

  group('TextUtils.isSimilarWord', () {
    test('short words require (near) exact match', () {
      expect(TextUtils.isSimilarWord('hell', 'help'), isFalse);
      expect(TextUtils.isSimilarWord('hell', 'hello'), isFalse);
      expect(TextUtils.isSimilarWord('on', 'in'), isFalse);
      expect(TextUtils.isSimilarWord('stop', 'stop'), isTrue);
    });

    test('longer words tolerate small mistranscriptions', () {
      expect(TextUtils.isSimilarWord('detecton', 'detection'), isTrue);
      expect(TextUtils.isSimilarWord('obstacle', 'obstacles'), isTrue);
      expect(TextUtils.isSimilarWord('detension', 'detection'), isTrue);
    });
  });
}
