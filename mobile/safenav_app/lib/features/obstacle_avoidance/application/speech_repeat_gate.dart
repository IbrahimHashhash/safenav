




















class SpeechRepeatGate {
  SpeechRepeatGate(this.cooldown);

  final Duration cooldown;
  final Map<String, _GateEntry> _lastSpokenAt = {};

  
  
  
  
  
  
  
  
  
  bool allow(
    String key,
    DateTime now, {
    double? distance,
    double distanceThreshold = 0.0,
  }) {
    if (key.isEmpty) return false;

    
    
    _lastSpokenAt.removeWhere((_, e) => now.difference(e.at) >= cooldown);

    final last = _lastSpokenAt[key];
    if (last != null) {
      final movedEnough = distanceThreshold > 0 &&
          distance != null &&
          last.distance != null &&
          (distance - last.distance!).abs() > distanceThreshold;
      if (!movedEnough) return false;
    }

    _lastSpokenAt[key] = _GateEntry(now, distance);
    return true;
  }

  
  void reset() => _lastSpokenAt.clear();

  
  
  
  
  
  
  static String keyFor({String? label, int? region, required String text}) {
    final normalizedLabel = (label ?? '').trim().toLowerCase();
    if (normalizedLabel.isNotEmpty) {
      return 'obstacle|$normalizedLabel|${region ?? -1}';
    }
    return 'text|${normalize(text)}';
  }

  
  static String normalize(String text) => text
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z ]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}



class _GateEntry {
  const _GateEntry(this.at, this.distance);
  final DateTime at;
  final double? distance;
}
