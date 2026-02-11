import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:crypto/crypto.dart';

/// Mock User Database Service
/// ใช้ SharedPreferences เก็บข้อมูลผู้ใช้ชั่วคราว (สำหรับ development)
/// ในโปรเจกต์จริงควรใช้ Rust backend + Database แทน
class MockUserDatabase {
  static const String _usersKey = 'mock_users_database';

  /// Get all users from local storage
  static Future<Map<String, String>> getAllUsers() async {
    final prefs = await SharedPreferences.getInstance();
    final usersJson = prefs.getString(_usersKey);
    
    if (usersJson == null) {
      // Return default mock users if no data exists
      return {
        'admin': _hashPassword('admin123'),
        'test': _hashPassword('test123'),
        'user': _hashPassword('user123'),
      };
    }
    
    final Map<String, dynamic> decoded = json.decode(usersJson);
    return Map<String, String>.from(decoded);
  }

  /// Add a new user to local storage
  static Future<bool> addUser(String username, String passwordHash) async {
    try {
      final users = await getAllUsers();
      
      // Check if username already exists
      if (users.containsKey(username.toLowerCase())) {
        return false; // Username already taken
      }
      
      // Add new user
      users[username.toLowerCase()] = passwordHash;
      
      // Save to SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_usersKey, json.encode(users));
      
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Check if username exists
  static Future<bool> userExists(String username) async {
    final users = await getAllUsers();
    return users.containsKey(username.toLowerCase());
  }

  /// Verify user credentials
  static Future<bool> verifyCredentials(String username, String passwordHash) async {
    final users = await getAllUsers();
    return users[username.toLowerCase()] == passwordHash;
  }

  /// Clear all users (for testing)
  static Future<void> clearAllUsers() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_usersKey);
  }

  // Helper function to hash password (same as AuthService)
  static String _hashPassword(String password) {
    // This should match the hashPassword function in AuthService
    final bytes = utf8.encode(password);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }
}
