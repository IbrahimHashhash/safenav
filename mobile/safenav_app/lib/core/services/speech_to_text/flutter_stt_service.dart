import 'dart:async';
import 'dart:typed_data';

import 'package:azure_stt_flutter/azure_stt_flutter.dart';
import 'package:record/record.dart';
import 'stt_service.dart';

/// Azure speech-to-text with a pre-roll microphone buffer.
///
/// The microphone is started (via [primeMic]) the instant the user taps, well
/// before the Azure WebSocket has connected. Captured PCM is pushed into a
/// single-subscription [StreamController], which buffers it until Azure
/// subscribes in [startListening]. Azure then receives the full pre-roll first,
/// followed by live audio — so the user's first word is never lost while the
/// session is still being established.
///
/// We pass this buffered stream to the plugin as its `externalAudioStream`,
/// which means the plugin does NOT start its own microphone — there is only one
/// active recorder (this one), so there is no contention.
class FlutterSttService implements SttService {
  final AzureSpeechToText _azureStt;
  final AudioRecorder _recorder = AudioRecorder();

  StreamController<Uint8List>? _audioController;
  StreamSubscription<Uint8List>? _micSubscription;
  StreamSubscription? _stateSubscription;
  String _lastText = '';
  bool _micActive = false;

  FlutterSttService(this._azureStt);

  @override
  bool get isListening => _azureStt.isListening;

  String get lastText => _lastText;

  @override
  Future<bool> initialize() async => true;

  /// Raw PCM format Azure expects (and that the recorder produces): 16 kHz,
  /// mono, 16-bit little-endian.
  ///
  /// `manageBluetooth: false` is critical: by default the recorder grabs
  /// Bluetooth SCO and toggles the Android audio-manager mode on every
  /// start/stop. That mode churn ducked/suppressed our cue sounds and TTS (and
  /// could leave audio playback stuck), so we opt out of it.
  static const RecordConfig _config = RecordConfig(
    encoder: AudioEncoder.pcm16bits,
    sampleRate: 16000,
    numChannels: 1,
    androidConfig: AndroidRecordConfig(manageBluetooth: false),
  );

  @override
  Future<void> primeMic() async {
    // Drop any previous capture session before starting a fresh one.
    await _stopMic();

    if (!await _recorder.hasPermission()) {
      throw Exception('Microphone permission not granted');
    }

    // A single-subscription controller buffers everything we capture now and
    // replays it to Azure once it subscribes in startListening().
    final controller = StreamController<Uint8List>();
    _audioController = controller;

    final micStream = await _recorder.startStream(_config);
    _micActive = true;

    _micSubscription = micStream.listen(
      (chunk) {
        if (!controller.isClosed) controller.add(chunk);
      },
      onError: (Object e) {
        if (!controller.isClosed) controller.addError(e);
      },
    );
  }

  @override
  Future<void> startListening({
    required Function(String text, bool isFinal) onResult,
    required Function() onTimeout,
    required Function(String message) onError,
  }) async {
    await _stateSubscription?.cancel();
    _lastText = '';

    final controller = _audioController;
    if (controller == null) {
      onError('Microphone was not primed before startListening');
      return;
    }

    _stateSubscription = _azureStt.transcriptionStateStream.listen(
      (state) {
        final intermediate = state.intermediateText.trim();
        if (intermediate.isNotEmpty) {
          onResult(intermediate, false);
        }

        final finalized = state.finalizedText.join(' ').trim();
        if (finalized.isNotEmpty) {
          _lastText = finalized;
          onResult(finalized, true);
        }
      },
      onError: (e) => onError(e.toString()),
      onDone: onTimeout,
    );

    // Feed Azure from the pre-roll buffer; the plugin will NOT open its own mic.
    await _azureStt.startListening(externalAudioStream: controller.stream);
  }

  @override
  Future<void> stopListening() async {
    await _azureStt.stopListening();
    await _stopMic();
    await _stateSubscription?.cancel();
    _stateSubscription = null;
  }

  Future<void> _stopMic() async {
    await _micSubscription?.cancel();
    _micSubscription = null;

    if (_micActive) {
      try {
        await _recorder.stop();
      } catch (_) {}
      _micActive = false;
    }

    final controller = _audioController;
    _audioController = null;
    if (controller != null && !controller.isClosed) {
      await controller.close();
    }
  }

  void dispose() {
    _stopMic();
    _azureStt.dispose();
    _recorder.dispose();
  }
}
