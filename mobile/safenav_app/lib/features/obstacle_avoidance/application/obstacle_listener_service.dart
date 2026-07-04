import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart' show HapticFeedback;

import '../../../core/services/camera/camera_frame_source.dart';
import '../../voice_interaction/presentation/cubit/voice_assistant_cubit.dart';
import '../data/capture_log_service.dart';
import '../data/datasources/navigation_ws_datasource.dart';
import '../domain/entities/detection_result.dart';
import 'detection_controller.dart';
import 'speech_repeat_gate.dart';



enum StreamStartResult { started, serverUnreachable, cameraUnavailable }








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

  
  
  static const Duration _repeatCooldown = Duration(seconds: 10);

  
  
  
  
  
  static const double _obstacleDistanceChangeM = 0.5;

  
  
  static const double _carCollisionDistanceM = 2.5;

  
  
  static const Duration _vibrationCooldown = Duration(seconds: 3);

  
  static const Duration _reconnectBudget = Duration(seconds: 4);
  static const Duration _reconnectRetryGap = Duration(milliseconds: 500);

  DateTime _lastVibrationAt = DateTime.fromMillisecondsSinceEpoch(0);

  StreamSubscription<DetectionResult>? _subscription;
  bool _running = false;
  bool _previewsEnabled = false;
  int _frameId = 0;

  
  int? _awaitingFrameId;
  Completer<void>? _responseWaiter;

  
  final Map<int, DateTime> _captureStartedAt = {};

  
  final Map<int, Uint8List> _captureBytes = {};

  
  bool _saveNextFrame = false;

  
  
  
  final SpeechRepeatGate _repeatGate = SpeechRepeatGate(_repeatCooldown);

  final StreamController<DetectionResult> _resultsController =
      StreamController<DetectionResult>.broadcast();
  final StreamController<String> _captureEventsController =
      StreamController<String>.broadcast();
  final StreamController<bool> _streamingController =
      StreamController<bool>.broadcast();
  DetectionResult? _lastResult;

  
  
  Uint8List? _lastFrameJpeg;
  Uint8List? get lastFrameJpeg => _lastFrameJpeg;

  Stream<DetectionResult> get results => _resultsController.stream;

  
  Stream<String> get captureEvents => _captureEventsController.stream;

  
  
  
  Stream<bool> get streamingChanges => _streamingController.stream;

  DetectionResult? get lastResult => _lastResult;

  bool get isStreaming => _running;
  String get serverUrl => datasource.url;

  

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

  
  Future<StreamStartResult> start() async {
    if (_running) return StreamStartResult.started;

    final ready = await _ensureReady();
    if (ready != StreamStartResult.started) {
      await _cleanupIfIdle();
      return ready;
    }

    _running = true;
    _emitStreaming(true);
    _repeatGate.reset();
    unawaited(_captureLoop());
    return StreamStartResult.started;
  }

  
  
  
  Future<String?> captureOnce() async {
    if (_running) {
      
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
    
    datasource.sendFrame(jpeg, id, includePreviews: true);
    return null;
  }

  Future<void> _captureLoop() async {
    while (_running) {
      final stopwatch = Stopwatch()..start();

      if (!datasource.isConnected) {
        
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

    
    final captureStart = _captureStartedAt.remove(result.frameId);
    if (captureStart != null) {
      result.endToEndMs =
          DateTime.now().difference(captureStart).inMicroseconds / 1000.0;
    }
    
    if (_captureStartedAt.length > 60) {
      final cutoff = result.frameId - 30;
      _captureStartedAt.removeWhere((id, _) => id < cutoff);
    }

    
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

    _maybeSpeak(result);
  }

  
  
  
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

  
  
  
  
  
  
  
  
  void _maybeSpeak(DetectionResult result) {
    final text = result.instruction.trim();
    if (text.isEmpty) return;

    final label = result.primaryLabel;
    final key = SpeechRepeatGate.keyFor(
      label: label,
      region: result.primaryRegionIndex(),
      text: text,
    );

    
    
    final hasObstacle = (label ?? '').trim().isNotEmpty;
    final distance = hasObstacle ? result.primaryDistanceMeters() : null;
    final threshold = hasObstacle ? _obstacleDistanceChangeM : 0.0;

    if (!_repeatGate.allow(
      key,
      DateTime.now(),
      distance: distance,
      distanceThreshold: threshold,
    )) {
      return;
    }

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
