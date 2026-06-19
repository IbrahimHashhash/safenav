import 'dart:async';

import '../../../core/services/camera/camera_frame_source.dart';
import '../../voice_interaction/presentation/cubit/voice_assistant_cubit.dart';
import '../data/datasources/navigation_ws_datasource.dart';
import '../domain/entities/detection_result.dart';

/// Outcome of attempting to start streaming, so the UI can show a precise
/// message about what went wrong.
enum StreamStartResult { started, serverUnreachable, cameraUnavailable }

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

  /// Target streaming rate. The capture loop paces itself to this period.
  static const int _targetFps = 3;
  static final Duration _framePeriod =
      Duration(milliseconds: (1000 / _targetFps).round());

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

  Stream<DetectionResult> get results => _resultsController.stream;
  DetectionResult? get lastResult => _lastResult;

  bool get isStreaming => _running;
  String get serverUrl => datasource.url;

  void setPreviewsEnabled(bool enabled) => _previewsEnabled = enabled;

  /// Starts streaming camera frames. Returns a [StreamStartResult] describing
  /// success or the specific failure (server vs camera).
  Future<StreamStartResult> start() async {
    if (_running) return StreamStartResult.started;
    _running = true;

    _subscription = datasource.stream.listen(_onResult);

    final connected = await datasource.connect();
    if (!connected) {
      await _teardown();
      return StreamStartResult.serverUnreachable;
    }

    final cameraReady = await cameraSource.initialize();
    if (!cameraReady) {
      await _teardown();
      await datasource.disconnect();
      return StreamStartResult.cameraUnavailable;
    }

    unawaited(_captureLoop());
    return StreamStartResult.started;
  }

  /// Captures and sends frames, paced to [_targetFps]. The wait after each
  /// frame is reduced by however long the capture+send already took, so the
  /// effective rate stays near the target instead of (period + capture time).
  Future<void> _captureLoop() async {
    while (_running) {
      final stopwatch = Stopwatch()..start();

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

      final remaining =
          _framePeriod.inMilliseconds - stopwatch.elapsedMilliseconds;
      if (remaining > 0) {
        await Future<void>.delayed(Duration(milliseconds: remaining));
      }
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
