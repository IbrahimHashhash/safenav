import 'package:flutter_bloc/flutter_bloc.dart';
import '../../application/voice_assistant_service.dart';
import 'voice_assistant_state.dart';

class VoiceAssistantCubit extends Cubit<VoiceAssistantState> {
  final VoiceAssistantService _service;

  VoiceAssistantCubit(this._service) : super(VoiceIdle()) {
    _service.onStateChange = (state) => emit(state);
  }

  Future<void> initialize() => _service.initialize();
  Future<void> startListening() => _service.startListening();
  Future<void> cancelListening() => _service.cancelListening();
  Future<void> speakObstacleInstruction(String text) => _service.speakObstacleInstruction(text);
  Future<void> speakNavigationInstruction(String text) => _service.speakNavigationInstruction(text);
}
