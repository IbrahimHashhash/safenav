import 'dart:async';

import '../../../core/services/camera/camera_frame_source.dart';
import '../../voice_interaction/presentation/cubit/voice_assistant_cubit.dart';
import '../data/datasources/navigation_ws_datasource.dart';
import '../domain/entities/obstacle_instruction.dart';

/// Drives the obstacle-avoidance loop:
///   camera frame -> WebSocket -> server -> JSON response ->
///   spoken `instruction` (via the shared TTS priority queue).
///
/// Obstacle speech goes through [VoiceAssistantCubit.speakObstacleInstruction],
/// which enqueues at the highest priority, so obstacle warnings preempt — and
/// never overlap — Mapbox navigation instructions on the single TTS engine.
class ObstacleListenerService {
  ObstacleListenerService({
    required this.datasource,
    required this.cameraSource,
    required this.voiceCubit,
  });

  final NavigationWebSocketDatasource datasource;
  final CameraFrameSource cameraSource;
  final VoiceAssistantCubit voiceCubit;

  /// Minimum delay between two capture attempts. takePicture() itself adds
  /// latency, so the effective rate is a few FPS — plenty, since the server
  /// also skips near-identical frames.
  static const Duration _captureInterval = Duration(milliseconds: 300);

  /// Don't repeat the *same* spoken instruction more often than this. A new,
  /// different instruction is spoken immediately (a new obstacle matters).
  static const Duration _repeatCooldown = Duration(seconds: 4);

  StreamSubscription<ObstacleInstruction>? _subscription;
  bool _running = false;
  int _frameId = 0;

  String _lastSpoken = '';
  DateTime _lastSpokenAt = DateTime.fromMillisecondsSinceEpoch(0);

  Future<void> start() async {
    if (_running) return;
    _running = true;

    _subscription = datasource.stream.listen(_onInstruction);

    final connected = await datasource.connect();
    if (!connected) {
      // Leave _running true so a later retry via start() is possible after
      // stop(); but without a connection there is nothing to capture for.
      _running = false;
      return;
    }

    final cameraReady = await cameraSource.initialize();
    if (!cameraReady) {
      _running = false;
      await _subscription?.cancel();
      _subscription = null;
      return;
    }

    unawaited(_captureLoop());
  }

  Future<void> _captureLoop() async {
    while (_running) {
      if (datasource.isConnected && cameraSource.isReady) {
        final jpeg = await cameraSource.captureJpeg();
        if (!_running) break;
        if (jpeg != null) {
          datasource.sendFrame(jpeg, _frameId);
          _frameId++;
        }
      }
      await Future<void>.delayed(_captureInterval);
    }
  }

  void _onInstruction(ObstacleInstruction instruction) {
    final text = instruction.message.trim();
    if (text.isEmpty) return;

    // De-duplicate: suppress an identical instruction repeated within the
    // cooldown, but let a different instruction through right away.
    final now = DateTime.now();
    if (text == _lastSpoken &&
        now.difference(_lastSpokenAt) < _repeatCooldown) {
      return;
    }
    _lastSpoken = text;
    _lastSpokenAt = now;

    voiceCubit.speakObstacleInstruction(text);
  }

  Future<void> stop() async {
    _running = false;
    await _subscription?.cancel();
    _subscription = null;
    await datasource.disconnect();
    await cameraSource.dispose();
  }
}
