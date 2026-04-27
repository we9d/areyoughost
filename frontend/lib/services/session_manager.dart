import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';

class SessionManager {
  // Use a per-instance namespace so multiple Windows clients on the same
  // machine can keep independent login sessions (Player 1 vs Player 2).
  static const String _sessionNamespace =
      String.fromEnvironment('SESSION_NAMESPACE', defaultValue: 'default');
  static final String _runtimeSessionNamespace =
      (Platform.environment['SESSION_NAMESPACE'] ?? _sessionNamespace).trim().isEmpty
          ? 'default'
          : (Platform.environment['SESSION_NAMESPACE'] ?? _sessionNamespace).trim();

  static const String _keyUserId = 'user_id';
  static const String _keyUsername = 'username';
  static const String _keyIsLoggedIn = 'is_logged_in';
  static const String _keyToken = 'access_token';

  static String _namespacedKey(String key) => '${_runtimeSessionNamespace}_$key';

  // Save session
  static Future<void> saveSession({
    required String userId,
    required String username,
    String? token,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_namespacedKey(_keyUserId), userId);
    await prefs.setString(_namespacedKey(_keyUsername), username);
    final hasToken = token != null && token.isNotEmpty;
    await prefs.setBool(_namespacedKey(_keyIsLoggedIn), hasToken);
    if (hasToken) {
      await prefs.setString(_namespacedKey(_keyToken), token);
    } else {
      await prefs.remove(_namespacedKey(_keyToken));
    }
  }

  // Get current session
  static Future<Map<String, String>?> getSession() async {
    final prefs = await SharedPreferences.getInstance();
    final isLoggedIn = prefs.getBool(_namespacedKey(_keyIsLoggedIn)) ?? false;
    
    if (!isLoggedIn) return null;

    final userId = prefs.getString(_namespacedKey(_keyUserId));
    final username = prefs.getString(_namespacedKey(_keyUsername));

    if (userId == null || username == null) return null;

    return {
      'userId': userId,
      'username': username,
      'token': prefs.getString(_namespacedKey(_keyToken)) ?? '',
    };
  }

  // Check if user is logged in
  static Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_namespacedKey(_keyIsLoggedIn)) ?? false;
  }

  // Clear session (logout)
  static Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_namespacedKey(_keyUserId));
    await prefs.remove(_namespacedKey(_keyUsername));
    await prefs.remove(_namespacedKey(_keyToken));
    await prefs.setBool(_namespacedKey(_keyIsLoggedIn), false);
  }

  // Get username
  static Future<String?> getUsername() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_namespacedKey(_keyUsername));
  }

  // Get user ID
  static Future<String?> getUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_namespacedKey(_keyUserId));
  }
}
