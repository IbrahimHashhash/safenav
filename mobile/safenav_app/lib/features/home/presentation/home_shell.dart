import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/di/injection.dart';
import '../../mapbox_navigation/presentation/cubit/navigation_map_cubit.dart';
import '../../obstacle_avoidance/application/obstacle_listener_service.dart';
import '../../voice_interaction/presentation/cubit/voice_assistant_cubit.dart';
import 'developer_screen.dart';
import 'user_screen.dart';

/// Root screen. Hosts the shared streaming state and a toggle between the
/// user-facing voice screen and the developer/debug screen.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.obstacleListener});

  final ObstacleListenerService obstacleListener;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  bool _devMode = false;
  bool _streaming = false;
  bool _togglingStream = false;

  @override
  void initState() {
    super.initState();
    context.read<VoiceAssistantCubit>().initialize();
    _streaming = widget.obstacleListener.isStreaming;
    // User screen does not need preview images.
    widget.obstacleListener.setPreviewsEnabled(false);
  }

  void _toggleScreen() {
    setState(() => _devMode = !_devMode);
    // Only fetch model previews from the server while the dev screen is shown.
    widget.obstacleListener.setPreviewsEnabled(_devMode);
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

  @override
  Widget build(BuildContext context) {
    return BlocProvider<NavigationMapCubit>(
      create: (_) => sl<NavigationMapCubit>(),
      child: Scaffold(
        appBar: AppBar(
          title:
              Text(_devMode ? 'Developer (debug)' : 'SafeNav Voice Assistant'),
          actions: [
            IconButton(
              tooltip: _devMode
                  ? 'Switch to user view'
                  : 'Switch to developer view',
              icon: Icon(_devMode ? Icons.person : Icons.bug_report),
              onPressed: _toggleScreen,
            ),
          ],
        ),
        body: _devMode
            ? DeveloperScreen(
                listener: widget.obstacleListener,
                streaming: _streaming,
                busy: _togglingStream,
                onToggleStreaming: _toggleStreaming,
              )
            : UserScreen(
                streaming: _streaming,
                busy: _togglingStream,
                onToggleStreaming: _toggleStreaming,
              ),
      ),
    );
  }
}
