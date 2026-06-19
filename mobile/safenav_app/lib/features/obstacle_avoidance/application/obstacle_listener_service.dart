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

  /// Safety cap: if a frame's response never arrives, stop waiting after this
  /// so the loop can't deadlock.
  static const Duration _responseTimeout = Duration(seconds: 2);

  static const Duration _repeatCooldown = Duration(seconds: 4);

  StreamSubscription<DetectionResult>? _subscription;
  bool _running = false;
  bool _previewsEnabled = false;
  int _frameId = 0;

  // Backpressure: at most one frame is in flight at a time. The capture loop
  // waits for the in-flight frame's response before sending the next, so the
  // server is always working on the most recent frame and instructions never
  // describe a scene from seconds ago.
  int? _awaitingFrameId;
  Completer<void>? _responseWaiter;

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

  /// Captures and sends frames with single-frame backpressure: after sending,
  /// it waits for that frame's response (or [_responseTimeout]) before the
  /// next capture, and additionally paces to at most [_targetFps].
  Future<void> _captureLoop() async {
    while (_running) {
      final stopwatch = Stopwatch()..start();

      if (!datasource.isConnected || !cameraSource.isReady) {
        await Future<void>.delayed(_framePeriod);
        continue;
      }

      final jpeg = await cameraSource.captureJpeg();
      if (!_running) break;

      if (jpeg != null) {
        final id = _frameId++;
        final waiter = Completer<void>();
        _awaitingFrameId = id;
        _responseWaiter = waiter;

        datasource.sendFrame(jpeg, id, includePreviews: _previewsEnabled);

        // Backpressure: don't send another frame until this one is answered.
        await waiter.future.timeout(_responseTimeout, onTimeout: () {});
        _responseWaiter = null;
        _awaitingFrameId = null;
      }

      // Upper-bound the rate so a fast server can't exceed the target FPS.
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

    // Release backpressure for the in-flight frame (>= guards against a lost
    // intermediate response).
    final awaiting = _awaitingFrameId;
    if (awaiting != null && result.frameId >= awaiting) {
      final waiter = _responseWaiter;
      if (waiter != null && !waiter.isCompleted) waiter.complete();
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
    final waiter = _responseWaiter;
    if (waiter != null && !waiter.isCompleted) waiter.complete();
    _responseWaiter = null;
    _awaitingFrameId = null;
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
