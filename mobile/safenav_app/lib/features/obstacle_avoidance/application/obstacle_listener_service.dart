import 'dart:async';

import '../../../core/services/camera/camera_frame_source.dart';
import '../../voice_interaction/presentation/cubit/voice_assistant_cubit.dart';
import '../data/datasources/navigation_ws_datasource.dart';
import '../domain/entities/detection_result.dart';

/// Drives the obstacle-avoidance loop:
///   camera frame -> WebSocket -> server -> JSON (+ optional previews) ->
///   spoken `instruction` (via the shared TTS priority queue).
///
/// Also re-publishes the full [DetectionResult] stream so the developer screen
/// can show previews, obstacles and metrics. Obstacle speech goes through
/// [VoiceAssistantCubit.speakObstacleInstruction] (highest priority), so it
/// preempts — and never overlaps — Mapbox navigation on the single TTS engine.
class ObstacleListenerService {
  ObstacleListenerService({
    required this.datasource,
    required this.cameraSource,
    required this.voiceCubit,
  });

  final NavigationWebSocketDatasource datasource;
  final CameraFrameSource cameraSource;
  final VoiceAssistantCubit voiceCubit;

  static const Duration _captureInterval = Duration(milliseconds: 300);
  static const Duration _repeatCooldown = Duration(seconds: 4);

  StreamSubscription<DetectionResult>? _subscription;
  bool _running = false;
  bool _previewsEnabled = false;
  int _frameId = 0;

  String _lastSpoken = '';
  DateTime _lastSpokenAt = DateTime.fromMillisecondsSinceEpoch(0);

  final StreamController<DetectionResult> _resultsController =
      StreamController<DetectionResult>.broadcast();
  DetectionResult? _lastResult;

  /// Full per-frame results, for the developer screen.
  Stream<DetectionResult> get results => _resultsController.stream;
  DetectionResult? get lastResult => _lastResult;

  bool get isStreaming => _running;

  /// When true, frames request the model preview images back from the server.
  /// Toggled on while the developer screen is visible.
  void setPreviewsEnabled(bool enabled) => _previewsEnabled = enabled;

  /// Starts streaming camera frames. Returns true if streaming began.
  Future<bool> start() async {
    if (_running) return true;
    _running = true;

    _subscription = datasource.stream.listen(_onResult);

    final connected = await datasource.connect();
    if (!connected) {
      await _teardown();
      return false;
    }

    final cameraReady = await cameraSource.initialize();
    if (!cameraReady) {
      await _teardown();
      await datasource.disconnect();
      return false;
    }

    unawaited(_captureLoop());
    return true;
  }

  Future<void> _captureLoop() async {
    while (_running) {
      if (datasource.isConnected && cameraSource.isReady) {
        final jpeg = await cameraSource.captureJpeg();
        if (!_running) break;
        if (jpeg != null) {
          datasource.sendFrame(
            jpeg,
            _frameId,
            includePreviews: _previewsEnabled,
          );
          _frameId++;
        }
      }
      await Future<void>.delayed(_captureInterval);
    }
  }

  void _onResult(DetectionResult result) {
    _lastResult = result;
    if (!_resultsController.isClosed) {
      _resultsController.add(result);
    }
    _maybeSpeak(result.instruction);
  }

  void _maybeSpeak(String instruction) {
    final text = instruction.trim();
    if (text.isEmpty) return;

    final now = DateTime.now();
    if (text == _lastSpoken &&
        now.difference(_lastSpokenAt) < _repeatCooldown) {
      return;
    }
    _lastSpoken = text;
    _lastSpokenAt = now;

    voiceCubit.speakObstacleInstruction(text);
  }

  Future<void> _teardown() async {
    _running = false;
    await _subscription?.cancel();
    _subscription = null;
  }

  Future<void> stop() async {
    await _teardown();
    await datasource.disconnect();
    await cameraSource.dispose();
  }

  void dispose() {
    stop();
    _resultsController.close();
  }
}
