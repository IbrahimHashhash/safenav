import 'package:shared_preferences/shared_preferences.dart';

/// Stores lightweight user profile data (currently just the name) and persists
/// it across sessions via shared_preferences, so the assistant can address the
/// user by name in later responses.
class UserProfileService {
  static const String _nameKey = 'user_name';

  SharedPreferences? _prefs;
  String? _name;

  String? get name => _name;
  bool get hasName => _name != null && _name!.trim().isNotEmpty;

  /// Loads the persisted profile. Call once at startup.
  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    _name = _prefs!.getString(_nameKey);
  }

  /// Persists the user's name.
  Future<void> setName(String name) async {
    final clean = name.trim();
    _name = clean;
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString(_nameKey, clean);
  }

  Future<void> clear() async {
    _name = null;
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.remove(_nameKey);
  }
}
