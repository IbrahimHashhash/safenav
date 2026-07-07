import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/di/injection.dart';
import '../../mapbox_navigation/presentation/cubit/navigation_map_cubit.dart';
import '../../obstacle_avoidance/application/obstacle_listener_service.dart';
import '../../voice_interaction/presentation/cubit/voice_assistant_cubit.dart';
import 'developer_screen.dart';
import 'recording_screen.dart';
import 'user_screen.dart';

/// Which top-level screen is shown.
enum _Screen { user, developer, recording }

/// Root screen. Hosts the shared streaming state and a toggle between the
/// user-facing voice screen, the developer/debug screen, and the screen-
/// recording view.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.obstacleListener});

  final ObstacleListenerService obstacleListener;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  _Screen _screen = _Screen.user;
  bool _streaming = false;
  bool _togglingStream = false;
  StreamSubscription<bool>? _streamingSub;

  @override
  void initState() {
    super.initState();
    final voice = context.read<VoiceAssistantCubit>();
    voice.initialize();
    // Greet the user on launch with the short how-to so they know how to
    // interact (tap to talk, available commands).
    voice.playWelcome();
    _streaming = widget.obstacleListener.isStreaming;
    // Keep the button in sync when detection is toggled by VOICE or stopped by
    // a network drop.
    _streamingSub = widget.obstacleListener.streamingChanges.listen((on) {
      if (mounted) setState(() => _streaming = on);
    });
    // User screen does not need preview images.
    widget.obstacleListener.setPreviewsEnabled(false);
  }

  @override
  void dispose() {
    _streamingSub?.cancel();
    super.dispose();
  }

  void _setScreen(_Screen screen) {
    setState(() => _screen = screen);
    // Only fetch model previews from the server while the dev screen is shown.
    widget.obstacleListener.setPreviewsEnabled(screen == _Screen.developer);
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

    final result = await widget.obstacleListener.start();
    if (!mounted) return;
    final started = result == StreamStartResult.started;
    setState(() {
      _streaming = started;
      _togglingStream = false;
    });
    if (!started) {
      final message = switch (result) {
        StreamStartResult.serverUnreachable =>
          'Cannot reach the detection server at '
              '${widget.obstacleListener.serverUrl}. '
              'Make sure it is running and on the same network.',
        StreamStartResult.cameraUnavailable =>
          'Camera unavailable. Grant the camera permission and try again.',
        StreamStartResult.started => '',
      };
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 5)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<NavigationMapCubit>(
      create: (_) => sl<NavigationMapCubit>(),
      child: Scaffold(
        appBar: AppBar(
          title: Text(switch (_screen) {
            _Screen.developer => 'Developer (debug)',
            _Screen.recording => 'Screen recording',
            _Screen.user => 'SafeNav Voice Assistant',
          }),
          actions: [
            IconButton(
              tooltip: _screen == _Screen.recording
                  ? 'Back to user view'
                  : 'Switch to screen-recording view',
              icon: Icon(_screen == _Screen.recording
                  ? Icons.videocam_off
                  : Icons.videocam),
              onPressed: () => _setScreen(_screen == _Screen.recording
                  ? _Screen.user
                  : _Screen.recording),
            ),
            IconButton(
              tooltip: _screen == _Screen.developer
                  ? 'Switch to user view'
                  : 'Switch to developer view',
              icon: Icon(
                  _screen == _Screen.developer ? Icons.person : Icons.bug_report),
              onPressed: () => _setScreen(_screen == _Screen.developer
                  ? _Screen.user
                  : _Screen.developer),
            ),
          ],
        ),
        body: switch (_screen) {
          _Screen.developer => DeveloperScreen(
              listener: widget.obstacleListener,
              streaming: _streaming,
              busy: _togglingStream,
              onToggleStreaming: _toggleStreaming,
            ),
          _Screen.recording => RecordingScreen(
              listener: widget.obstacleListener,
              streaming: _streaming,
            ),
          _Screen.user => const UserScreen(),
        },
      ),
    );
  }
}
