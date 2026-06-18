import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../obstacle_avoidance/application/obstacle_listener_service.dart';
import '../cubit/voice_assistant_cubit.dart';
import '../cubit/voice_assistant_state.dart';
import '../widgets/idle_view.dart';
import '../widgets/listening_view.dart';
import '../widgets/processing_view.dart';
import '../widgets/speaking_view.dart';

class VoiceAssistantPage extends StatefulWidget {
  const VoiceAssistantPage({super.key, required this.obstacleListener});

  final ObstacleListenerService obstacleListener;

  @override
  State<VoiceAssistantPage> createState() => _VoiceAssistantPageState();
}

class _VoiceAssistantPageState extends State<VoiceAssistantPage> {
  bool _streaming = false;
  bool _togglingStream = false;

  String _inputCaption = '';
  String _replyCaption = '';

  @override
  void initState() {
    super.initState();
    context.read<VoiceAssistantCubit>().initialize();
    _streaming = widget.obstacleListener.isStreaming;
  }

  Future<void> _toggleStreaming() async {
    if (_togglingStream) return;
    setState(() => _togglingStream = true);

    if (_streaming) {
      await widget.obstacleListener.stop();
      if (!mounted) return;
      setState(() {
        _streaming = false;
        _togglingStream = false;
      });
      return;
    }

    final started = await widget.obstacleListener.start();
    if (!mounted) return;
    setState(() {
      _streaming = started;
      _togglingStream = false;
    });
    if (!started) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not start obstacle detection. '
            'Check the camera permission and that the server is reachable.',
          ),
        ),
      );
    }
  }

  void _onVoiceTap(VoiceAssistantState state) {
    final cubit = context.read<VoiceAssistantCubit>();
    if (state is VoiceListening) {
      cubit.cancelListening();
    } else if (state is VoiceSpeaking) {
      cubit.stopSpeaking();
    } else {
      // Idle, processing or error -> start a new listen.
      cubit.startListening();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('SafeNav Voice Assistant')),
      body: BlocConsumer<VoiceAssistantCubit, VoiceAssistantState>(
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

              // Top: start/stop streaming frames to the server.
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: _StreamingButton(
                      streaming: _streaming,
                      busy: _togglingStream,
                      onPressed: _toggleStreaming,
                    ),
                  ),
                ),
              ),

              // Bottom: captions for input speech and spoken reply.
              // Display-only, so taps pass through to the push-to-talk surface.
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: SafeArea(
                  top: false,
                  child: IgnorePointer(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _CaptionCard(
                            label: 'You said',
                            text: _inputCaption,
                            icon: Icons.mic,
                            accent: const Color(0xFF2979FF),
                          ),
                          const SizedBox(height: 10),
                          _CaptionCard(
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
              ),
            ],
          );
        },
      ),
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

class _StreamingButton extends StatelessWidget {
  const _StreamingButton({
    required this.streaming,
    required this.busy,
    required this.onPressed,
  });

  final bool streaming;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final label = streaming
        ? 'Stop obstacle detection'
        : 'Start obstacle detection';

    return Semantics(
      button: true,
      label: label,
      child: ElevatedButton.icon(
        onPressed: busy ? null : onPressed,
        icon: busy
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Icon(streaming ? Icons.stop : Icons.videocam),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          minimumSize: const Size.fromHeight(54),
          backgroundColor:
              streaming ? Colors.red.shade700 : Colors.green.shade700,
          foregroundColor: Colors.white,
          textStyle:
              const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}

class _CaptionCard extends StatelessWidget {
  const _CaptionCard({
    required this.label,
    required this.text,
    required this.icon,
    required this.accent,
  });

  final String label;
  final String text;
  final IconData icon;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final hasText = text.trim().isNotEmpty;
    return Semantics(
      liveRegion: true,
      label: hasText ? '$label: $text' : null,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: accent.withValues(alpha: 0.6)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: accent, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: accent,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    hasText ? text : '—',
                    style: TextStyle(
                      color: hasText ? Colors.white : Colors.white38,
                      fontSize: 16,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
