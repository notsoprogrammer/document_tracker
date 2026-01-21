import 'package:shared_preferences/shared_preferences.dart';
import '../config/auth_config.dart';

class AuthService {
  static const String _authorizedKey = 'isAuthorized';
  static const String _usernameKey = 'username';

  static Future<bool> isAuthorized() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_authorizedKey) ?? false;
  }

  static Future<void> setAuthorized(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_authorizedKey, value);
  }

  static bool validatePassword(String password) {
    return password == developerPassword;
  }

  static Future<String?> getUsername() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_usernameKey);
  }

  static Future<void> setUsername(String username) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_usernameKey, username);
  }
}
