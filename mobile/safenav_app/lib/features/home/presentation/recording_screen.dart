import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../shared/widgets/caption_card.dart';
import '../../mapbox_navigation/presentation/widgets/navigation_map_view.dart';
import '../../obstacle_avoidance/application/obstacle_listener_service.dart';
import '../../voice_interaction/presentation/cubit/voice_assistant_cubit.dart';
import '../../voice_interaction/presentation/cubit/voice_assistant_state.dart';

/// A single-screen layout meant to be screen-recorded during testing:
///   • camera scene preview (top) — the camera is on but NOT streamed to the
///     server, it's just to see the scene,
///   • the live navigation map with the route and the orientation cursor
///     (middle) — rendered non-interactive so it never intercepts touches,
///   • captions for the user's speech and the assistant's reply (bottom).
///
/// The whole screen is a push-to-talk surface: tapping anywhere starts/stops
/// listening, exactly like the user screen.
class RecordingScreen extends StatefulWidget {
  const RecordingScreen({
    super.key,
    required this.listener,
    required this.streaming,
  });

  final ObstacleListenerService listener;

  /// Whether the detection pipeline is streaming (and therefore already owns
  /// the camera). Used so we never dispose a camera the pipeline is using.
  final bool streaming;

  @override
  State<RecordingScreen> createState() => _RecordingScreenState();
}

class _RecordingScreenState extends State<RecordingScreen> {
  String _inputCaption = '';

  // True when this screen started the camera just for the scene preview (so we
  // release it on dispose, but never while streaming owns it).
  bool _camStartedByMe = false;

  @override
  void initState() {
    super.initState();
    _ensureCameraPreview();
  }

  @override
  void dispose() {
    if (_camStartedByMe && !widget.streaming) {
      widget.listener.cameraSource.dispose();
    }
    super.dispose();
  }

  /// Turns the camera on for the scene preview without streaming to the server.
  /// No-op if streaming already owns the camera.
  Future<void> _ensureCameraPreview() async {
    final cam = widget.listener.cameraSource;
    if (cam.isReady) return;
    final ok = await cam.initialize();
    if (ok) _camStartedByMe = true;
    if (mounted) setState(() {});
  }

  void _onVoiceTap(VoiceAssistantState state) {
    final cubit = context.read<VoiceAssistantCubit>();
    if (state is VoiceListening) {
      cubit.cancelListening();
    } else {
      // Any other state: a tap means "let me talk now". startListening()
      // silences whatever is speaking and opens the mic.
      cubit.startListening();
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<VoiceAssistantCubit, VoiceAssistantState>(
      listener: (context, state) {
        if (state is VoiceProcessing && state.input.isNotEmpty) {
          setState(() => _inputCaption = state.input);
        } else if (state is VoiceIdle || state is VoiceListening) {
          if (_inputCaption.isNotEmpty) setState(() => _inputCaption = '');
        }
      },
      builder: (context, state) {
        final replyText = state is VoiceSpeaking ? state.text : '';
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _onVoiceTap(state),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Camera scene preview.
                  _cameraPreview(MediaQuery.of(context).size.height * 0.30),
                  const SizedBox(height: 8),
                  // Map fills the remaining space; IgnorePointer keeps it
                  // non-interactive so taps fall through to push-to-talk.
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: const IgnorePointer(
                        child: NavigationMapView(showCoordinates: true),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Captions: what the user said and what the assistant replied.
                  _caption(
                    'You said',
                    _inputCaption,
                    Icons.mic,
                    const Color(0xFF2979FF),
                  ),
                  const SizedBox(height: 8),
                  _caption(
                    'Assistant',
                    replyText,
                    Icons.volume_up,
                    const Color(0xFF9C4DFF),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _cameraPreview(double height) {
    final cam = widget.listener.cameraSource;
    final ready = cam.isReady && cam.previewSize != null;
    return SizedBox(
      height: height,
      width: double.infinity,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: ready
            ? FittedBox(
                fit: BoxFit.cover,
                clipBehavior: Clip.hardEdge,
                child: SizedBox(
                  width: cam.previewSize!.height,
                  height: cam.previewSize!.width,
                  child: cam.buildPreview(),
                ),
              )
            : Container(
                color: Colors.white10,
                alignment: Alignment.center,
                child: const Text(
                  'Starting camera…',
                  style: TextStyle(color: Colors.white70),
                ),
              ),
      ),
    );
  }

  Widget _caption(String label, String text, IconData icon, Color accent) {
    return CaptionCard(
      label: label,
      text: text.isEmpty ? '—' : text,
      icon: icon,
      accent: accent,
    );
  }
}
