import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:areyoughost/services/session_manager.dart';
import 'package:areyoughost/services/rust_api.dart';
import 'package:areyoughost/src/rust/models.dart';

class AuthService {
  // Global auth state
  static final ValueNotifier<User?> currentUser = ValueNotifier<User?>(null);

  // Username validation: Allow any characters
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
    if (username.length > 50) {
      return 'ชื่อผู้ใช้ต้องไม่เกิน 50 ตัวอักษร';
    }

    return null; // Valid
  }

  // Password validation: Allow any characters
  static String? validatePassword(String? password) {
    if (password == null || password.isEmpty) {
      return 'กรุณากรอกรหัสผ่าน';
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

  // Check login status on app start
  static Future<void> checkLoginStatus() async {
    final session = await SessionManager.getSession();
    if (session != null) {
      // Restore user state from session
      // Note: We create a partial User object here since we don't store full info in session
      // Ideally, we might want to fetch full profile from API if possible, but this is enough for UI display
      currentUser.value = User(
        userId: session['userId']!,
        username: session['username']!,
        passwordHash: '', // Not needed for display
        createdAt: '', // Not needed for display
        lastLogin: null,
      );
    } else {
      currentUser.value = null;
    }
  }

  // Login function
  static Future<Map<String, dynamic>> login({
    required String username,
    required String password,
  }) async {
    // Validate username
    final usernameError = validateUsername(username);
    if (usernameError != null) {
      return {'success': false, 'error': usernameError};
    }

    // Validate password
    final passwordError = validatePassword(password);
    if (passwordError != null) {
      return {'success': false, 'error': passwordError};
    }

    final hashedPassword = hashPassword(password);

    try {
      final user = await RustApi.instance.login(
        username: username,
        password: hashedPassword,
      );

      // Login successful
      final userId = user.userId;

      // Save session
      await SessionManager.saveSession(userId: userId, username: user.username);

      // Update state
      currentUser.value = user;

      return {'success': true, 'userId': userId, 'username': user.username};
    } catch (e) {
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
      return {'success': false, 'error': usernameError};
    }

    // Validate password
    final passwordError = validatePassword(password);
    if (passwordError != null) {
      return {'success': false, 'error': passwordError};
    }

    // Hash password
    final hashedPassword = hashPassword(password);

    try {
      final user = await RustApi.instance.register(
        username: username,
        password: hashedPassword,
      );

      final userId = user.userId;

      // Save session
      await SessionManager.saveSession(userId: userId, username: user.username);

      // Update state
      currentUser.value = user;

      return {'success': true, 'userId': userId, 'username': user.username};
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
    currentUser.value = null;
  }

  // Update username function
  static Future<Map<String, dynamic>> updateUsername(String newUsername) async {
    final user = currentUser.value;
    if (user == null) {
      return {'success': false, 'error': 'ยังไม่ได้ทำการเข้าสู่ระบบ'};
    }

    // Validate new username
    final usernameError = validateUsername(newUsername);
    if (usernameError != null) {
      return {'success': false, 'error': usernameError};
    }

    try {
      await RustApi.instance.updateUsername(
        userId: user.userId,
        newUsername: newUsername,
      );

      // Update session and state
      await SessionManager.saveSession(
        userId: user.userId,
        username: newUsername,
      );

      // Create new user object with updated username
      currentUser.value = User(
        userId: user.userId,
        username: newUsername,
        passwordHash: user.passwordHash,
        createdAt: user.createdAt,
        lastLogin: user.lastLogin,
      );

      return {'success': true};
    } catch (e) {
      return {
        'success': false,
        'error': e.toString().replaceAll('Exception: ', ''),
      };
    }
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
