import 'dart:async';
import 'dart:typed_data';

import 'package:azure_stt_flutter/azure_stt_flutter.dart';
import 'package:record/record.dart';
import 'stt_service.dart';













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

  
  
  
  
  
  
  
  static const RecordConfig _config = RecordConfig(
    encoder: AudioEncoder.pcm16bits,
    sampleRate: 16000,
    numChannels: 1,
    
    
    
    
    
    autoGain: true,
    noiseSuppress: true,
    echoCancel: true,
    androidConfig: AndroidRecordConfig(
      manageBluetooth: false,
      
      
      audioSource: AndroidAudioSource.voiceRecognition,
    ),
  );

  @override
  Future<void> primeMic() async {
    
    await _stopMic();

    if (!await _recorder.hasPermission()) {
      throw Exception('Microphone permission not granted');
    }

    
    
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
