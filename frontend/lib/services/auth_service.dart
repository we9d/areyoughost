import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:areyoughost/services/session_manager.dart';
import 'package:areyoughost/services/rust_api.dart';
// import 'package:areyoughost/services/mock_user_database.dart'; // Removed

class AuthService {
  // Username validation: alphanumeric only, no spaces, no special characters
  static String? validateUsername(String? username) {
    if (username == null || username.trim().isEmpty) {
      return 'กรุณากรอกชื่อผู้ใช้งาน';
    }

    // Check for spaces or special characters (allow alphanumeric, underscores, and Thai)
    // Using Unicode range for Thai: \u0E00-\u0E7F which covers consonants, vowels, and tone marks
    final validPattern = RegExp(r'^[a-zA-Z0-9_\u0E00-\u0E7F]+$');
    if (!validPattern.hasMatch(username)) {
      return 'ไม่สามารถใช้สัญลักษณ์พิเศษได้ (อนุญาตเฉพาะตัวอักษร, ตัวเลข, _ และภาษาไทย)';
    }

    // Minimum length
    if (username.length < 3) {
      return 'ชื่อผู้ใช้ต้องมีอย่างน้อย 3 ตัวอักษร';
    }

    // Maximum length
    if (username.length > 20) {
      return 'ชื่อผู้ใช้ต้องไม่เกิน 20 ตัวอักษร';
    }

    return null; // Valid
  }

  // Password validation: English only
  static String? validatePassword(String? password) {
    if (password == null || password.isEmpty) {
      return 'กรุณากรอกรหัสผ่าน';
    }

    // Check for Thai characters
    final thaiPattern = RegExp(r'[ก-๙]');
    if (thaiPattern.hasMatch(password)) {
      return 'กรุณากรอกภาษาอังกฤษ';
    }

    // Check for spaces
    if (password.contains(' ')) {
      return 'ไม่สามารถใช้ช่องว่าง กรุณาลองใหม่อีกครั้ง';
    }

    // Minimum length for security
    if (password.length < 4) {
      return 'รหัสผ่านต้องมีอย่างน้อย 4 ตัวอักษร';
    }

    return null; // Valid
  }

  // Hash password using SHA-256
  static String hashPassword(String password) {
    final bytes = utf8.encode(password);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  // Login function
  static Future<Map<String, dynamic>> login({
    required String username,
    required String password,
  }) async {
    // Validate username
    final usernameError = validateUsername(username);
    if (usernameError != null) {
      return {
        'success': false,
        'error': usernameError,
      };
    }

    // Validate password
    final passwordError = validatePassword(password);
    if (passwordError != null) {
      return {
        'success': false,
        'error': passwordError,
      };
    }

    // Hash password (Client side hash mainly for avoiding plain text in memory/transit if not using TLS, 
    // but usually better to send plain over TLS and hash in backend.
    // However, backend expects hashed password for now? 
    // Wait, backend `login` implementation in api.rs checks `user.password_hash == password`.
    // It expects whatever we send to match DB.
    // In `register`, it stores `password_hash = password`.
    // So if frontend hashes, backend stores hash.
    // I'll keep client-side hashing to match existing logic.)
    final hashedPassword = hashPassword(password);

    try {
      final user = await RustApi.instance.login(username: username, password: hashedPassword);
      
      // Login successful
      final userId = user.userId; // Now String

      // Save session
      await SessionManager.saveSession(
        userId: userId,
        username: user.username,
      );

      return {
        'success': true,
        'userId': userId,
        'username': user.username,
      };
    } catch (e) {
       // Extract helpful message if possible
       return {
        'success': false,
        'error': e.toString().replaceAll('Exception: ', ''),
      };
    }
  }

  // Register function
  static Future<Map<String, dynamic>> register({
    required String username,
    required String password,
  }) async {
    // Validate username
    final usernameError = validateUsername(username);
    if (usernameError != null) {
      return {
        'success': false,
        'error': usernameError,
      };
    }

    // Note: Rust `register` method will check availability/uniqueness constraints via DB UNIQUE constraint.
    // So we don't need separate checkUsernameAvailability call anymore, we can just catch the error.

    // Validate password
    final passwordError = validatePassword(password);
    if (passwordError != null) {
      return {
        'success': false,
        'error': passwordError,
      };
    }

    // Hash password
    final hashedPassword = hashPassword(password);

    try {
      final user = await RustApi.instance.register(username: username, password: hashedPassword);
      
      final userId = user.userId; // Now String

      // Save session
      await SessionManager.saveSession(
        userId: userId,
        username: user.username,
      );

      return {
        'success': true,
        'userId': userId,
        'username': user.username,
      };
    } catch (e) {
      return {
        'success': false,
        'error': e.toString().replaceAll('Exception: ', ''),
      };
    }
  }

  // Logout function
  static Future<void> logout() async {
    await SessionManager.clearSession();
  }

  // Check if user is logged in
  static Future<bool> isLoggedIn() async {
    return await SessionManager.isLoggedIn();
  }

  // Get current user
  static Future<Map<String, String>?> getCurrentUser() async {
    return await SessionManager.getSession();
  }
}
