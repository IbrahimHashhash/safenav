import 'package:flutter_tts/flutter_tts.dart';
import 'package:get_it/get_it.dart';
import 'package:azure_stt_flutter/azure_stt_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../../features/voice_interaction/application/voice_assistant_service.dart';
import '../../features/voice_interaction/domain/usecases/extract_location_usecase.dart';
import '../../features/voice_interaction/domain/usecases/parse_intent_usecase.dart';
import '../../features/obstacle_avoidance/data/datasources/obstacle_sse_datasource.dart';

import '../services/speech_to_text/flutter_stt_service.dart';
import '../services/speech_to_text/stt_service.dart';
import '../services/text_to_speech/flutter_tts_service.dart';
import '../services/text_to_speech/tts_service.dart';

final sl = GetIt.instance;

Future<void> initDependencies() async {
  sl.registerLazySingleton(() => FlutterTts());

  sl.registerLazySingleton(
    () => AzureSpeechToText(
      subscriptionKey: dotenv.env['AZURE_SPEECH_KEY'] ?? '',
      region: dotenv.env['AZURE_SPEECH_REGION'] ?? 'eastus',
      languages: ['en-US'],
    ),
  );

  sl.registerLazySingleton<TtsService>(
    () => FlutterTtsService(sl()),
  );

  sl.registerLazySingleton<SttService>(
    () => FlutterSttService(sl()),
  );

  sl.registerLazySingleton(() => ParseIntentUseCase());
  sl.registerLazySingleton(() => ExtractLocationUseCase());

  sl.registerLazySingleton(
    () => VoiceAssistantService(
      sttService: sl(),
      ttsService: sl(),
      parseIntent: sl(),
      extractLocation: sl(),
    ),
  );

  sl.registerLazySingleton(
    () => ObstacleSseDatasource(
      baseUrl: dotenv.env['OBSTACLE_API_URL'] ?? 'http://10.0.2.2:8000',
    ),
  );
}