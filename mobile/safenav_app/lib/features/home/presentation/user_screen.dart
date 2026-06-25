import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../shared/widgets/caption_card.dart';
import '../../voice_interaction/presentation/cubit/voice_assistant_cubit.dart';
import '../../voice_interaction/presentation/cubit/voice_assistant_state.dart';
import '../../voice_interaction/presentation/widgets/idle_view.dart';
import '../../voice_interaction/presentation/widgets/listening_view.dart';
import '../../voice_interaction/presentation/widgets/processing_view.dart';
import '../../voice_interaction/presentation/widgets/speaking_view.dart';

/// User-facing screen: a full-screen push-to-talk surface and captions for the
/// recognized input and the spoken reply. Obstacle detection is controlled by
/// voice ("start/stop detection") here — its button lives on the dev screen.
class UserScreen extends StatefulWidget {
  const UserScreen({super.key});

  @override
  State<UserScreen> createState() => _UserScreenState();
}

class _UserScreenState extends State<UserScreen> {
  String _inputCaption = '';
  String _replyCaption = '';

  void _onVoiceTap(VoiceAssistantState state) {
    final cubit = context.read<VoiceAssistantCubit>();
    if (state is VoiceListening) {
      cubit.cancelListening();
    } else {
      // Idle, speaking, processing or error: push-to-talk starts listening.
      // startListening() interrupts any ongoing speech so the user can talk.
      cubit.startListening();
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<VoiceAssistantCubit, VoiceAssistantState>(
      listener: (context, state) {
        if (state is VoiceProcessing && state.input.isNotEmpty) {
          setState(() => _inputCaption = state.input);
        } else if (state is VoiceSpeaking && state.text.isNotEmpty) {
          setState(() => _replyCaption = state.text);
        }
      },
      builder: (context, state) {
        return Stack(
          children: [
            // Push-to-talk fills the whole screen.
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _onVoiceTap(state),
                child: _CenterView(state: state),
              ),
            ),

            // Bottom: captions for input speech and spoken reply.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CaptionCard(
                        label: 'You said',
                        text: _inputCaption,
                        icon: Icons.mic,
                        accent: const Color(0xFF2979FF),
                      ),
                      const SizedBox(height: 10),
                      CaptionCard(
                        label: 'Assistant',
                        text: _replyCaption,
                        icon: Icons.volume_up,
                        accent: const Color(0xFF9C4DFF),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _CenterView extends StatelessWidget {
  const _CenterView({required this.state});

  final VoiceAssistantState state;

  @override
  Widget build(BuildContext context) {
    if (state is VoiceListening) return const ListeningView();
    if (state is VoiceProcessing) return const ProcessingView();
    if (state is VoiceSpeaking) return const SpeakingView();
    if (state is VoiceError) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            (state as VoiceError).message,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
        ),
      );
    }
    return const IdleView();
  }
}
