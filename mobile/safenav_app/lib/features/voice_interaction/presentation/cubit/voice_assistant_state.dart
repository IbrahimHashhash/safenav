abstract class VoiceAssistantState {}

class VoiceIdle extends VoiceAssistantState {}

class VoiceListening extends VoiceAssistantState {}

/// Recognized user speech is being handled (intent parsing, route building,
/// etc.). Carries the transcript so the UI can caption what the user said.
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
