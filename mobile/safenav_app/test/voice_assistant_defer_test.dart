import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safenav_app/core/services/speech_to_text/stt_service.dart';
import 'package:safenav_app/core/services/text_to_speech/tts_service.dart';
import 'package:safenav_app/core/services/compass/compass_service.dart';
import 'package:safenav_app/features/mapbox_navigation/application/navigation_service.dart';
import 'package:safenav_app/features/mapbox_navigation/domain/entities/route_entity.dart';
import 'package:safenav_app/features/mapbox_navigation/domain/repositories/route_repository.dart';
import 'package:safenav_app/features/mapbox_navigation/domain/usecases/get_route_usecase.dart';
import 'package:safenav_app/features/voice_interaction/application/voice_assistant_service.dart';
import 'package:safenav_app/features/voice_interaction/domain/usecases/extract_location_usecase.dart';
import 'package:safenav_app/features/voice_interaction/domain/usecases/parse_intent_usecase.dart';

class FakeTts implements TtsService {
  VoidCallback? _onComplete;
  String? speaking;
  final List<String> started = [];

  @override
  Future<void> speak(String text, {VoidCallback? onComplete}) async {
    speaking = text;
    started.add(text);
    _onComplete = onComplete;
  }

  @override
  Future<void> stop() async {
    speaking = null;
    _onComplete = null;
  }

  void finish() {
    final cb = _onComplete;
    speaking = null;
    _onComplete = null;
    cb?.call();
  }
}

class FakeStt implements SttService {
  bool _listening = false;
  Function(String, bool)? onResult;

  @override
  bool get isListening => _listening;

  @override
  Future<bool> initialize() async => true;

  @override
  Future<void> startListening({
    required Function(String text, bool isFinal) onResult,
    required Function() onTimeout,
    required Function(String message) onError,
  }) async {
    _listening = true;
    this.onResult = onResult;
  }

  @override
  Future<void> stopListening() async {
    _listening = false;
  }
}

class FakeCompass implements CompassService {
  @override
  Stream<double?> get headingStream => const Stream.empty();
  @override
  double? get currentHeading => null;
  @override
  Future<void> dispose() async {}
}

class FakeRouteRepository implements RouteRepository {
  @override
  Future<RouteEntity> getRoute({
    required double sourceLat,
    required double sourceLng,
    required double destLat,
    required double destLng,
  }) async {
    throw UnimplementedError();
  }
}

VoiceAssistantService buildService(SttService stt, FakeTts tts) {
  final nav = NavigationService(
    getRoute: GetRouteUseCase(FakeRouteRepository()),
    compass: FakeCompass(),
    onInstruction: (_) {},
  );
  return VoiceAssistantService(
    sttService: stt,
    ttsService: tts,
    parseIntent: ParseIntentUseCase(),
    extractLocation: ExtractLocationUseCase(),
    navigationService: nav,
  );
}

class OrderedStt implements SttService {
  final List<String> log = [];
  int _concurrent = 0;
  int maxConcurrent = 0;
  bool _listening = false;

  @override
  bool get isListening => _listening;

  @override
  Future<bool> initialize() async => true;

  @override
  Future<void> startListening({
    required Function(String text, bool isFinal) onResult,
    required Function() onTimeout,
    required Function(String message) onError,
  }) =>
      _op('start', () => _listening = true);

  @override
  Future<void> stopListening() => _op('stop', () => _listening = false);

  Future<void> _op(String name, void Function() effect) async {
    _concurrent++;
    if (_concurrent > maxConcurrent) maxConcurrent = _concurrent;
    await Future<void>.delayed(const Duration(milliseconds: 5));
    effect();
    log.add(name);
    _concurrent--;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  for (final name in const [
    'xyz.luan/audioplayers.global',
    'xyz.luan/audioplayers',
  ]) {
    messenger.setMockMethodCallHandler(
      MethodChannel(name),
      (call) async => null,
    );
  }

  test('obstacle is deferred (not spoken) while listening', () async {
    final stt = FakeStt();
    final tts = FakeTts();
    final service = buildService(stt, tts);

    await service.startListening();
    await service.speakObstacleInstruction('obstacle ahead');
    await pumpEventQueue();

    expect(stt.isListening, isTrue);
    expect(tts.speaking, isNull);
    expect(tts.started, isEmpty);
  });

  test('deferred obstacle plays after a command, command response not lost', () async {
    final stt = FakeStt();
    final tts = FakeTts();
    final service = buildService(stt, tts);

    await service.startListening();
    await service.speakObstacleInstruction('obstacle ahead');

    stt.onResult!('help', true);
    await pumpEventQueue();

    expect(tts.speaking, 'obstacle ahead');
    expect(tts.started.contains('obstacle ahead'), isTrue);

    tts.finish();
    await pumpEventQueue();

    expect(tts.started.length, greaterThanOrEqualTo(2));
    expect(tts.started.last, isNot('obstacle ahead'));
  });

  test('cancelListening flushes a deferred obstacle', () async {
    final stt = FakeStt();
    final tts = FakeTts();
    final service = buildService(stt, tts);

    await service.startListening();
    await service.speakObstacleInstruction('obstacle ahead');
    await service.cancelListening();
    await pumpEventQueue();

    expect(stt.isListening, isFalse);
    expect(tts.speaking, 'obstacle ahead');
  });

  test('obstacle plays immediately when not listening', () async {
    final stt = FakeStt();
    final tts = FakeTts();
    final service = buildService(stt, tts);

    await service.speakObstacleInstruction('obstacle ahead');
    await pumpEventQueue();

    expect(tts.speaking, 'obstacle ahead');
  });

  test('rapid start/cancel/start never overlaps and ends listening', () async {
    final stt = OrderedStt();
    final tts = FakeTts();
    final service = buildService(stt, tts);

    final f1 = service.startListening();
    final f2 = service.cancelListening();
    final f3 = service.startListening();
    await Future.wait([f1, f2, f3]);
    await pumpEventQueue();

    expect(stt.maxConcurrent, 1);
    expect(stt.log.last, 'start');
    expect(stt.isListening, isTrue);
  });
}
