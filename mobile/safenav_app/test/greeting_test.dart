import 'package:flutter_test/flutter_test.dart';
import 'package:safenav_app/features/voice_interaction/application/voice_command_handler.dart';
import 'package:safenav_app/features/voice_interaction/domain/entities/voice_command.dart';
import 'package:safenav_app/features/voice_interaction/domain/usecases/parse_intent_usecase.dart';

void main() {
  group('ParseIntentUseCase greeting', () {
    final parse = ParseIntentUseCase();

    test('plain greetings are detected', () {
      expect(parse('hello'), VoiceCommandType.greeting);
      expect(parse('hi'), VoiceCommandType.greeting);
      expect(parse('hey there'), VoiceCommandType.greeting);
      expect(parse('good morning'), VoiceCommandType.greeting);
    });

    test('a command with a greeting word still routes to the command', () {
      // "hey navigate to the library" must be navigation, not a greeting.
      expect(parse('hey navigate to the library'), VoiceCommandType.navigate);
    });

    test('non-greeting stays unknown', () {
      expect(parse('blah blah'), VoiceCommandType.unknown);
    });
  });

  group('ParseIntentUseCase detection', () {
    final parse = ParseIntentUseCase();

    test('start/enable detection variants', () {
      expect(parse('start detection'), VoiceCommandType.startDetection);
      expect(parse('begin obstacle detection'),
          VoiceCommandType.startDetection);
      expect(parse('enable detection'), VoiceCommandType.startDetection);
    });

    test('stop/disable detection variants', () {
      expect(parse('stop detection'), VoiceCommandType.stopDetection);
      expect(parse('disable obstacle detection'),
          VoiceCommandType.stopDetection);
      expect(parse('turn off detection'), VoiceCommandType.stopDetection);
    });

    test('navigation commands are not mistaken for detection', () {
      expect(parse('start navigation'), VoiceCommandType.startNavigation);
      expect(parse('stop navigation'), VoiceCommandType.stopNavigation);
    });
  });

  group('extractSpokenName', () {
    test('extracts a bare name', () {
      expect(extractSpokenName('John'), 'John');
    });

    test('strips common lead-in phrases', () {
      expect(extractSpokenName('my name is Sara'), 'Sara');
      expect(extractSpokenName("I'm Alex"), 'Alex');
      expect(extractSpokenName('call me Sam'), 'Sam');
      expect(extractSpokenName('this is Maria'), 'Maria');
    });

    test('keeps up to two words and capitalizes', () {
      expect(extractSpokenName('my name is mary jane'), 'Mary Jane');
    });

    test('ignores greeting/stop words around the name', () {
      expect(extractSpokenName('hello, I am Omar'), 'Omar');
    });

    test('returns null when no name remains', () {
      expect(extractSpokenName('my name is'), isNull);
      expect(extractSpokenName(''), isNull);
      expect(extractSpokenName('hello'), isNull);
    });
  });
}
