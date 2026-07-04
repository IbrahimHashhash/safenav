abstract class VoiceAssistantState {}

class VoiceIdle extends VoiceAssistantState {}

class VoiceListening extends VoiceAssistantState {}



class VoiceProcessing extends VoiceAssistantState {
  final String input;

  VoiceProcessing(this.input);
}

class VoiceSpeaking extends VoiceAssistantState {
  final String text;

  VoiceSpeaking(this.text);
}

class VoiceError extends VoiceAssistantState {
  final String message;

  VoiceError(this.message);
}
