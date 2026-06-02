import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

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
    return BlocBuilder<VoiceAssistantCubit, VoiceAssistantState>(
      builder: (context, state) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Campus Voice Assistant'),
          ),
          body: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              final cubit = context.read<VoiceAssistantCubit>();

              if (state is VoiceIdle) {
                // Start listening — command will fire automatically on silence
                cubit.startListening();
              } else if (state is VoiceListening) {
                // Tap during listening = CANCEL (not submit)
                // VAD handles submission; this is the abort escape hatch
                cubit.cancelListening();
              } else if (state is VoiceSpeaking) {
                // Tap during speaking = interrupt TTS
                cubit.stopSpeaking();
              }
            },
            child: () {
              if (state is VoiceListening) return const ListeningView();
              if (state is VoiceSpeaking) return SpeakingView();
              if (state is VoiceError) return Center(child: Text(state.message));
              return const IdleView();
            }(),
          ),
        );
      },
    );
  }
}