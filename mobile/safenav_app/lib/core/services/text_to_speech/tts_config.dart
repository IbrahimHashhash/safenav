class TtsConfig {
  final String language;
  final double speechRate;
  final double pitch;
  final double volume;

  const TtsConfig({
    this.language = 'en-GB',
    this.speechRate = 0.5,
    this.pitch = 1.0,
    this.volume = 1.0,
  });
}