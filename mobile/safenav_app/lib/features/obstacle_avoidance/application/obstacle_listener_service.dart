import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart' show HapticFeedback;

import '../../../core/services/camera/camera_frame_source.dart';
import '../../voice_interaction/presentation/cubit/voice_assistant_cubit.dart';
import '../data/capture_log_service.dart';
import '../data/datasources/navigation_ws_datasource.dart';
import '../domain/entities/detection_result.dart';
import 'detection_controller.dart';

/// Outcome of attempting to start streaming, so the UI can show a precise
/// message about what went wrong.
enum StreamStartResult { started, serverUnreachable, cameraUnavailable }

/// Drives the obstacle-avoidance loop:
///   camera frame -> WebSocket -> server -> JSON (+ optional previews) ->
///   spoken `instruction` (via the shared TTS priority queue).
///
/// Also: re-publishes the full [DetectionResult] stream (dev screen), supports
/// single-shot captures that persist the frame + metrics, and measures
/// end-to-end latency from frame capture to response.
class ObstacleListenerService implements DetectionController {
  ObstacleListenerService({
    required this.datasource,
    required this.cameraSource,
    required this.voiceCubit,
    required this.captureLog,
  });

  final NavigationWebSocketDatasource datasource;
  final CameraFrameSource cameraSource;
  final VoiceAssistantCubit voiceCubit;
  final CaptureLogService captureLog;

  static const int _targetFps = 3;
  static final Duration _framePeriod =
      Duration(milliseconds: (1000 / _targetFps).round());
  static const Duration _responseTimeout = Duration(seconds: 2);

  /// Suppress an identical, unchanged spoken instruction (e.g. "path clear")
  /// for this long so it isn't repeated every couple of seconds.
  static const Duration _repeatCooldown = Duration(seconds: 6);

  /// A car closer than this (meters) is treated as an imminent collision and
  /// triggers a single vibration.
  static const double _carCollisionDistanceM = 2.5;

  /// Minimum gap between collision vibrations so it doesn't buzz continuously
  /// while the car stays close.
  static const Duration _vibrationCooldown = Duration(seconds: 3);

  /// On a network drop, try to reconnect for up to this long before giving up.
  static const Duration _reconnectBudget = Duration(seconds: 4);
  static const Duration _reconnectRetryGap = Duration(milliseconds: 500);

  DateTime _lastVibrationAt = DateTime.fromMillisecondsSinceEpoch(0);

  StreamSubscription<DetectionResult>? _subscription;
  bool _running = false;
  bool _previewsEnabled = false;
  int _frameId = 0;

  // Backpressure: at most one streamed frame in flight at a time.
  int? _awaitingFrameId;
  Completer<void>? _responseWaiter;

  // Capture-to-response latency: frame capture start time, keyed by frame id.
  final Map<int, DateTime> _captureStartedAt = {};

  // Frames whose JPEG must be persisted when their response arrives.
  final Map<int, Uint8List> _captureBytes = {};

  // When streaming, persist the very next streamed frame on a capture request.
  bool _saveNextFrame = false;

  String _lastSpoken = '';
  DateTime _lastSpokenAt = DateTime.fromMillisecondsSinceEpoch(0);

  final StreamController<DetectionResult> _resultsController =
      StreamController<DetectionResult>.broadcast();
  final StreamController<String> _captureEventsController =
      StreamController<String>.broadcast();
  final StreamController<bool> _streamingController =
      StreamController<bool>.broadcast();
  DetectionResult? _lastResult;

  /// The most recent JPEG frame sent to the server (clean, no overlays), used
  /// by the dev screen as the free-zone overlay background.
  Uint8List? _lastFrameJpeg;
  Uint8List? get lastFrameJpeg => _lastFrameJpeg;

  Stream<DetectionResult> get results => _resultsController.stream;

  /// Human-readable messages about saved captures (for snackbars).
  Stream<String> get captureEvents => _captureEventsController.stream;

  /// Emits whenever streaming turns on (true) / off (false), including when
  /// toggled by voice or stopped by a network drop, so the UI button stays in
  /// sync.
  Stream<bool> get streamingChanges => _streamingController.stream;

  DetectionResult? get lastResult => _lastResult;

  bool get isStreaming => _running;
  String get serverUrl => datasource.url;

  // --- DetectionController (used by the voice command handler) -------------

  @override
  bool get isDetecting => _running;

  @override
  Future<bool> startDetection() async =>
      (await start()) == StreamStartResult.started;

  @override
  Future<void> stopDetection() => stop();

  void setPreviewsEnabled(bool enabled) => _previewsEnabled = enabled;

  void _emitStreaming(bool value) {
    if (!_streamingController.isClosed) _streamingController.add(value);
  }

  void _ensureSubscribed() {
    _subscription ??= datasource.stream.listen(_onResult);
  }

  /// Connect + initialise camera. Returns the specific failure, if any.
  Future<StreamStartResult> _ensureReady() async {
    _ensureSubscribed();
    if (!datasource.isConnected) {
      if (!await datasource.connect()) {
        return StreamStartResult.serverUnreachable;
      }
    }
    if (!cameraSource.isReady) {
      if (!await cameraSource.initialize()) {
        return StreamStartResult.cameraUnavailable;
      }
    }
    return StreamStartResult.started;
  }

  Future<void> _cleanupIfIdle() async {
    if (_running) return;
    await _subscription?.cancel();
    _subscription = null;
    await datasource.disconnect();
  }

  /// Starts continuous streaming. Returns success or the specific failure.
  Future<StreamStartResult> start() async {
    if (_running) return StreamStartResult.started;

    final ready = await _ensureReady();
    if (ready != StreamStartResult.started) {
      await _cleanupIfIdle();
      return ready;
    }

    _running = true;
    _emitStreaming(true);
    unawaited(_captureLoop());
    return StreamStartResult.started;
  }

  /// Captures a single frame, sends it to the server, and persists it (frame +
  /// metrics) when the response arrives. Works whether or not streaming is on.
  /// Returns null on success, or an error message.
  Future<String?> captureOnce() async {
    if (_running) {
      // Already streaming: persist the next streamed frame.
      _saveNextFrame = true;
      return null;
    }

    final ready = await _ensureReady();
    if (ready == StreamStartResult.serverUnreachable) {
      await _cleanupIfIdle();
      return 'Cannot reach the detection server at $serverUrl.';
    }
    if (ready == StreamStartResult.cameraUnavailable) {
      await _cleanupIfIdle();
      return 'Camera unavailable. Grant the camera permission and try again.';
    }

    final captureStart = DateTime.now();
    final jpeg = await cameraSource.captureJpeg();
    if (jpeg == null) {
      return 'Camera is busy. Try again in a moment.';
    }

    final id = _frameId++;
    _captureStartedAt[id] = captureStart;
    _captureBytes[id] = jpeg;
    _lastFrameJpeg = jpeg;
    // Always request previews for a capture so they can be saved with the frame.
    datasource.sendFrame(jpeg, id, includePreviews: true);
    return null;
  }

  Future<void> _captureLoop() async {
    while (_running) {
      final stopwatch = Stopwatch()..start();

      if (!datasource.isConnected) {
        // Network drop while the user wants detection: try to recover.
        final resumed = await _awaitReconnect();
        if (!_running) break;
        if (resumed) {
          voiceCubit.speakObstacleInstruction(
              'Back online. Obstacle detection resumed.');
          continue;
        }
        voiceCubit.speakObstacleInstruction(
            'Obstacle detection stopped because the internet disconnected.');
        await stop();
        break;
      }

      if (!cameraSource.isReady) {
        await Future<void>.delayed(_framePeriod);
        continue;
      }

      final captureStart = DateTime.now();
      final jpeg = await cameraSource.captureJpeg();
      if (!_running) break;

      if (jpeg != null) {
        _lastFrameJpeg = jpeg;
        final id = _frameId++;
        _captureStartedAt[id] = captureStart;
        final saveThisFrame = _saveNextFrame;
        if (saveThisFrame) {
          _captureBytes[id] = jpeg;
          _saveNextFrame = false;
        }

        final waiter = Completer<void>();
        _awaitingFrameId = id;
        _responseWaiter = waiter;

        // Request previews when the dev screen wants them, or when this frame
        // is being captured (so its previews are saved with it).
        datasource.sendFrame(
          jpeg,
          id,
          includePreviews: _previewsEnabled || saveThisFrame,
        );

        await waiter.future.timeout(_responseTimeout, onTimeout: () {});
        _responseWaiter = null;
        _awaitingFrameId = null;
      }

      final remaining =
          _framePeriod.inMilliseconds - stopwatch.elapsedMilliseconds;
      if (remaining > 0) {
        await Future<void>.delayed(Duration(milliseconds: remaining));
      }
    }
  }

  /// Tries to reconnect within [_reconnectBudget]. Returns true if reconnected.
  Future<bool> _awaitReconnect() async {
    final deadline = DateTime.now().add(_reconnectBudget);
    while (_running && DateTime.now().isBefore(deadline)) {
      if (await datasource.connect()) return true;
      await Future<void>.delayed(_reconnectRetryGap);
    }
    return datasource.isConnected;
  }

  void _onResult(DetectionResult result) {
    _lastResult = result;

    // End-to-end latency measured from frame CAPTURE to response.
    final captureStart = _captureStartedAt.remove(result.frameId);
    if (captureStart != null) {
      result.endToEndMs =
          DateTime.now().difference(captureStart).inMicroseconds / 1000.0;
    }
    // Guard against leaks if some responses are lost.
    if (_captureStartedAt.length > 60) {
      final cutoff = result.frameId - 30;
      _captureStartedAt.removeWhere((id, _) => id < cutoff);
    }

    // Persist this frame if it was a capture request.
    final bytes = _captureBytes.remove(result.frameId);
    if (bytes != null) {
      unawaited(_saveCapture(bytes, result));
    }

    if (!_resultsController.isClosed) {
      _resultsController.add(result);
    }

    _maybeVibrateForCar(result);

    final awaiting = _awaitingFrameId;
    if (awaiting != null && result.frameId >= awaiting) {
      final waiter = _responseWaiter;
      if (waiter != null && !waiter.isCompleted) waiter.complete();
    }

    _maybeSpeak(result.instruction);
  }

  /// Single vibration when a CAR is very close (imminent collision / path
  /// blocking). Uses the car's own distance when available, otherwise the
  /// clearance of the free-zone region the car blocks. Debounced.
  void _maybeVibrateForCar(DetectionResult result) {
    final now = DateTime.now();
    if (now.difference(_lastVibrationAt) < _vibrationCooldown) return;

    if (!result.hasCar) return;
    final distance = result.carDistanceMeters();
    if (distance == null || distance > _carCollisionDistanceM) return;

    _lastVibrationAt = now;
    try {
      HapticFeedback.vibrate();
    } catch (_) {
      // No haptics available; ignore.
    }
  }

  Future<void> _saveCapture(Uint8List jpeg, DetectionResult result) async {
    try {
      final record = await captureLog.save(
        frameJpeg: jpeg,
        result: result,
        capturedAt: DateTime.now(),
      );
      final previews =
          record.previewCount > 0 ? ' + ${record.previewCount} previews' : '';
      final gallery = record.gallerySaved > 0
          ? ' · ${record.gallerySaved} saved to gallery'
          : '';
      _emitCaptureEvent('Saved frame #${record.frameId} '
          '(${record.imageFileName})$previews$gallery');
    } catch (e) {
      _emitCaptureEvent('Failed to save capture: $e');
    }
  }

  void _emitCaptureEvent(String message) {
    if (!_captureEventsController.isClosed) {
      _captureEventsController.add(message);
    }
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
    _saveNextFrame = false;
    await _subscription?.cancel();
    _subscription = null;
  }

  Future<void> stop() async {
    final wasRunning = _running;
    await _teardown();
    await datasource.disconnect();
    await cameraSource.dispose();
    if (wasRunning) _emitStreaming(false);
  }

  void dispose() {
    stop();
    _resultsController.close();
    _captureEventsController.close();
    _streamingController.close();
  }
}
