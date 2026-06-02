import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'core/di/injection.dart';

import 'features/obstacle_avoidance/data/datasources/obstacle_sse_datasource.dart';
import 'features/obstacle_avoidance/application/obstacle_listener_service.dart';
import 'features/voice_interaction/presentation/cubit/voice_assistant_cubit.dart';
import 'features/voice_interaction/presentation/pages/voice_assistant_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');
  await initDependencies();

  final voiceCubit = VoiceAssistantCubit(sl());

  final obstacleListener = ObstacleListenerService(
    datasource: sl<ObstacleSseDatasource>(),
    voiceCubit: voiceCubit,
  );
  runApp(MyApp(voiceCubit: voiceCubit, obstacleListener: obstacleListener));
}

class MyApp extends StatefulWidget {
  final VoiceAssistantCubit voiceCubit;
  final ObstacleListenerService obstacleListener;

  const MyApp({
    super.key,
    required this.voiceCubit,
    required this.obstacleListener,
  });

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void dispose() {
    widget.obstacleListener.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider.value(value: widget.voiceCubit),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark(),
        home: const VoiceAssistantPage(),
      ),
    );
  }
}