import 'package:flutter_tts/flutter_tts.dart';
import 'package:get_it/get_it.dart';
import 'package:azure_stt_flutter/azure_stt_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../../features/voice_interaction/application/voice_assistant_service.dart';
import '../../features/voice_interaction/domain/usecases/extract_location_usecase.dart';
import '../../features/voice_interaction/domain/usecases/parse_intent_usecase.dart';
import '../../features/obstacle_avoidance/data/datasources/obstacle_sse_datasource.dart';
import '../../features/mapbox_navigation/application/navigation_service.dart';
import '../../features/mapbox_navigation/data/data_sources/mapbox_datasource.dart';
import '../../features/mapbox_navigation/data/repositories/campus_route_repository_impl.dart';
import '../../features/mapbox_navigation/domain/repositories/route_repository.dart';
import '../../features/mapbox_navigation/domain/usecases/get_route_usecase.dart';
import '../../features/mapbox_navigation/presentation/cubit/navigation_map_cubit.dart';

import '../services/compass/compass_service.dart';
import '../services/compass/flutter_compass_service.dart';
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

  sl.registerLazySingleton<TtsService>(() => FlutterTtsService(sl()));
  sl.registerLazySingleton<SttService>(() => FlutterSttService(sl()));
  sl.registerLazySingleton<CompassService>(() => FlutterCompassService());

  sl.registerLazySingleton(() => ParseIntentUseCase());
  sl.registerLazySingleton(() => ExtractLocationUseCase());

  sl.registerLazySingleton(
    () => MapboxDataSource(dotenv.env['MAPBOX_ACCESS_TOKEN'] ?? ''),
  );
  sl.registerLazySingleton<RouteRepository>(
    () => CampusRouteRepositoryImpl(sl()),
  );
  sl.registerLazySingleton(() => GetRouteUseCase(sl()));

  sl.registerLazySingleton(
    () => NavigationService(
      getRoute: sl(),
      compass: sl<CompassService>(),
      onInstruction: (instruction) {
        sl<VoiceAssistantService>().speakNavigationInstruction(instruction);
      },
    ),
  );

  sl.registerLazySingleton(
    () => VoiceAssistantService(
      sttService: sl(),
      ttsService: sl(),
      parseIntent: sl(),
      extractLocation: sl(),
      navigationService: sl(),
    ),
  );

  sl.registerFactory(() => NavigationMapCubit(sl<NavigationService>()));

  sl.registerLazySingleton(
    () => ObstacleSseDatasource(
      baseUrl: dotenv.env['OBSTACLE_API_URL'] ?? 'http://10.0.2.2:8000',
    ),
  );
}
