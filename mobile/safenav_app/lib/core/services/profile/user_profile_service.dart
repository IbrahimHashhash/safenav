import 'package:shared_preferences/shared_preferences.dart';




class UserProfileService {
  static const String _nameKey = 'user_name';

  SharedPreferences? _prefs;
  String? _name;

  String? get name => _name;
  bool get hasName => _name != null && _name!.trim().isNotEmpty;

  
  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    _name = _prefs!.getString(_nameKey);
  }

  
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
