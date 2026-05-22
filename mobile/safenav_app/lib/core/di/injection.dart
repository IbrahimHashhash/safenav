import 'package:flutter_tts/flutter_tts.dart';
import 'package:get_it/get_it.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../services/intent_parser/intent_parser_service.dart';
import '../services/speech_to_text/flutter_stt_service.dart';
import '../services/speech_to_text/stt_service.dart';
import '../services/text_to_speech/flutter_tts_service.dart';
import '../services/text_to_speech/tts_service.dart';

final sl = GetIt.instance;

Future<void> initDependencies() async {
  sl.registerLazySingleton(
    () => FlutterTts(),
  );

  sl.registerLazySingleton(
    () => SpeechToText(),
  );

  sl.registerLazySingleton<TtsService>(
    () => FlutterTtsService(sl()),
  );

  sl.registerLazySingleton<SttService>(
    () => FlutterSttService(sl()),
  );

  sl.registerLazySingleton(
    () => IntentParserService(),
  );
}