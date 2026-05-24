import 'dart:async';

import '../../voice_interaction/presentation/cubit/voice_assistant_cubit.dart';
import '../data/datasources/obstacle_sse_datasource.dart';

class ObstacleListenerService {
  final ObstacleSseDatasource datasource;
  final VoiceAssistantCubit voiceCubit;

  StreamSubscription? _subscription;

  ObstacleListenerService({
    required this.datasource,
    required this.voiceCubit,
  });

  Future<void> start() async {
    _subscription = datasource.stream.listen((instruction) {
      print('[ObstacleListener] forwarding to cubit: "${instruction.message}"');
      voiceCubit.speakObstacleInstruction(instruction.message);
    });

    
    await datasource.connect();
  }

  void stop() {
    _subscription?.cancel();
    _subscription = null;
    datasource.disconnect();
  }
}
