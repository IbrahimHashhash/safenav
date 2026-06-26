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
    } else if (state is VoiceSpeaking) {
      cubit.stopSpeaking();
    } else {
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
        } else if (state is VoiceIdle || state is VoiceListening) {
          // A new turn (or going idle): drop the previous captions so they
          // fade away instead of lingering statically on screen.
          if (_inputCaption.isNotEmpty || _replyCaption.isNotEmpty) {
            setState(() {
              _inputCaption = '';
              _replyCaption = '';
            });
          }
        }
      },
      builder: (context, state) {
        // Captions are not static: the "You said" card shows only while the
        // turn is being processed/spoken, and "Assistant" only while speaking.
        final showInput =
            (state is VoiceProcessing || state is VoiceSpeaking) &&
                _inputCaption.isNotEmpty;
        final showReply = state is VoiceSpeaking && _replyCaption.isNotEmpty;

        final cards = <Widget>[];
        if (showInput) {
          cards.add(
            CaptionCard(
              key: const ValueKey('caption-input'),
              label: 'You said',
              text: _inputCaption,
              icon: Icons.mic,
              accent: const Color(0xFF2979FF),
            ),
          );
        }
        if (showReply) {
          if (cards.isNotEmpty) cards.add(const SizedBox(height: 10));
          cards.add(
            CaptionCard(
              key: const ValueKey('caption-reply'),
              label: 'Assistant',
              text: _replyCaption,
              icon: Icons.volume_up,
              accent: const Color(0xFF9C4DFF),
            ),
          );
        }

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
            // Wrapped in IgnorePointer so taps over the captions fall through
            // to the full-screen push-to-talk GestureDetector above. The cards
            // stay visible and are still announced by TalkBack via Semantics.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: IgnorePointer(
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      child: cards.isEmpty
                          ? const SizedBox.shrink()
                          : Column(
                              key: ValueKey('captions-$showInput-$showReply'),
                              mainAxisSize: MainAxisSize.min,
                              children: cards,
                            ),
                    ),
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
