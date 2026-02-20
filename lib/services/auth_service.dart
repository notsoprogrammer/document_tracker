import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bcrypt/bcrypt.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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

  // Signup with username, password, and device token
  static Future<bool> signup(String username, String password, String? deviceToken) async {
    try {
      // First check if username already exists
      final existingUser = await Supabase.instance.client
          .from('users')
          .select('id')
          .eq('username', username)
          .maybeSingle();

      if (existingUser != null) {
        print('Username already exists: $username');
        return false; // Username is taken
      }

      // Hash the password
      final hashedPassword = BCrypt.hashpw(password, BCrypt.gensalt());

      // Insert user into Supabase
      final response = await Supabase.instance.client.from('users').insert({
        'username': username,
        'password_hash': hashedPassword,
      }).select().single();

      final userId = response['id'];

      // Save device token
      if (deviceToken != null) {
        await Supabase.instance.client.from('device_tokens').insert({
          'user_id': userId,
          'username': username,
          'token': deviceToken,
        });
      }

      // Set user as authorized and save username
      await setAuthorized(true);
      await setUsername(username);

      return true;
    } catch (e) {
      print('Signup error: $e');
      return false;
    }
  }

  // Login with username, password, and device token
  static Future<bool> login(String username, String password, String? deviceToken) async {
    try {
      print('Attempting login for user: $username');

      // Fetch user from Supabase
      final response = await Supabase.instance.client
          .from('users')
          .select('id, password_hash')
          .eq('username', username)
          .single();

      final userId = response['id'];
      final storedHash = response['password_hash'];


      // Verify password
      if (!BCrypt.checkpw(password, storedHash)) {
        print('Password verification failed');
        return false;
      }

      print('Password verified successfully');

      // Update or insert device token
      await Supabase.instance.client
          .from('device_tokens')
          .upsert({
            'user_id': userId,
            'username': username,
            'token': deviceToken,
          }, onConflict: 'user_id');

      // Set user as authorized and save username
      await setAuthorized(true);
      await setUsername(username);

      print('Login successful for user: $username');
      return true;
    } catch (e) {
      print('Login error: $e');
      return false;
    }
  }

  // Request password reset
  static Future<String?> requestPasswordReset(String username) async {
    try {
      // Check if user exists
      final userResponse = await Supabase.instance.client
          .from('users')
          .select('id')
          .eq('username', username)
          .single();

      final userId = userResponse['id'];

      // Generate reset token
      final resetToken = _generateResetToken();
      print('Generated reset token: $resetToken for user: $username');

      // Set expiry (15 minutes from now)
      final expiresAt = DateTime.now().add(const Duration(minutes: 15));

      // Insert reset record
      await Supabase.instance.client.from('password_resets').insert({
        'user_id': userId,
        'token': resetToken,
        'expires_at': expiresAt.toIso8601String(),
      });

      // print('Inserted reset record for token: $resetToken');
      return resetToken;
    } catch (e) {
      print('Password reset request error: $e');
      return null;
    }
  }

  // Reset password with token
  static Future<bool> resetPassword(String token, String newPassword, String? deviceToken) async {
    try {
      // Find valid reset record
      final resetResponse = await Supabase.instance.client
          .from('password_resets')
          .select('user_id, expires_at')
          .eq('token', token)
          .single();

      final userId = resetResponse['user_id'];
      final expiresAt = DateTime.parse(resetResponse['expires_at']);

      // Check if token is expired
      if (DateTime.now().isAfter(expiresAt)) {
        return false;
      }

      // Hash new password
      final hashedPassword = BCrypt.hashpw(newPassword, BCrypt.gensalt());

      // Update user password
      await Supabase.instance.client
          .from('users')
          .update({'password_hash': hashedPassword})
          .eq('id', userId);

      // Get username for automatic login
      final userResponse = await Supabase.instance.client
          .from('users')
          .select('username')
          .eq('id', userId)
          .single();

      final username = userResponse['username'];

      // Delete reset record
      await Supabase.instance.client
          .from('password_resets')
          .delete()
          .eq('token', token);

      // Automatically log the user in after password reset
      if (deviceToken != null) {
        await Supabase.instance.client.from('device_tokens').upsert({
          'user_id': userId,
          'username': username,
          'token': deviceToken,
          'updated_at': DateTime.now().toIso8601String(),
        }, onConflict: 'user_id');
      }

      // Set user as authorized and save username
      await setAuthorized(true);
      await setUsername(username);

      return true;
    } catch (e) {
      print('Password reset error: $e');
      return false;
    }
  }

  // Helper function to generate reset token
  static String _generateResetToken() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random.secure();
    return List.generate(8, (index) => chars[random.nextInt(chars.length)]).join();
  }
}
