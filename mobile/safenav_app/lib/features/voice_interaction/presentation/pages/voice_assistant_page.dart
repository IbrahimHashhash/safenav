import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../../../../core/di/injection.dart';
import '../../../mapbox_navigation/presentation/cubit/navigation_map_cubit.dart';
import '../../../mapbox_navigation/presentation/widgets/navigation_map_view.dart';
import '../cubit/voice_assistant_cubit.dart';
import '../cubit/voice_assistant_state.dart';
import '../widgets/idle_view.dart';
import '../widgets/listening_view.dart';
import '../widgets/speaking_view.dart';

class VoiceAssistantPage extends StatefulWidget {
  const VoiceAssistantPage({super.key});

  @override
  State<VoiceAssistantPage> createState() => _VoiceAssistantPageState();
}

class _VoiceAssistantPageState extends State<VoiceAssistantPage> {
  @override
  void initState() {
    super.initState();
    context.read<VoiceAssistantCubit>().initialize();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<NavigationMapCubit>(
      create: (_) => sl<NavigationMapCubit>(),
      child: Scaffold(
        appBar: AppBar(title: const Text('Campus Voice Assistant')),
        body: Column(
          children: [
            // Live navigation map with route and orientation arrow.
            Expanded(
              flex: 3,
              child: NavigationMapView(
                mapboxToken: dotenv.env['MAPBOX_ACCESS_TOKEN'] ?? '',
              ),
            ),
            // Voice interaction surface (tap to talk / cancel / stop).
            Expanded(
              flex: 2,
              child: BlocBuilder<VoiceAssistantCubit, VoiceAssistantState>(
                builder: (context, state) {
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      final cubit = context.read<VoiceAssistantCubit>();
                      if (state is VoiceIdle) {
                        cubit.startListening();
                      } else if (state is VoiceListening) {
                        cubit.cancelListening();
                      } else if (state is VoiceSpeaking) {
                        cubit.stopSpeaking();
                      }
                    },
                    child: () {
                      if (state is VoiceListening) return const ListeningView();
                      if (state is VoiceSpeaking) return SpeakingView();
                      if (state is VoiceError) {
                        return Center(child: Text(state.message));
                      }
                      return const IdleView();
                    }(),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
