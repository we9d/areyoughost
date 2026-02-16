import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:areyoughost/services/session_manager.dart';
import 'package:areyoughost/services/mock_user_database.dart';

class AuthService {
  // Username validation: Allow any characters
  static String? validateUsername(String? username) {
    if (username == null || username.trim().isEmpty) {
      return 'กรุณากรอกชื่อผู้ใช้งาน';
    }

    // Check for spaces or special characters (allow alphanumeric and underscores)
    final validPattern = RegExp(r'^[a-zA-Z0-9_]+$');
    if (!validPattern.hasMatch(username)) {
      return 'ไม่สามารถใช้สัญลักษณ์พิเศษได้ กรุณาลองใหม่อีกครั้ง';
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

  // Login function (mock for now, will connect to Rust backend later)
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

    // Hash password
    final hashedPassword = hashPassword(password);

    // TODO: Call Rust backend API for authentication
    // For now, use mock database from SharedPreferences
    await Future.delayed(const Duration(milliseconds: 500));

    // Check if username exists in database
    final userExists = await MockUserDatabase.userExists(username);
    if (!userExists) {
      return {
        'success': false,
        'error': 'ชื่อผู้ใช้หรือรหัสผ่านไม่ถูกต้อง',
      };
    }

    // Check if password matches
    final isValid = await MockUserDatabase.verifyCredentials(username, hashedPassword);
    if (!isValid) {
      return {
        'success': false,
        'error': 'ชื่อผู้ใช้หรือรหัสผ่านไม่ถูกต้อง',
      };
    }

    // Login successful - Mock user data
    final userId = DateTime.now().millisecondsSinceEpoch.toString();

    // Save session
    await SessionManager.saveSession(
      userId: userId,
      username: username,
    );

    return {
      'success': true,
      'userId': userId,
      'username': username,
    };
  }

  /// Check if username is already taken in database
  /// Returns true if username is available, false if already taken
  static Future<bool> checkUsernameAvailability(String username) async {
    // TODO: Call Rust backend API to check username availability
    // For now, check against mock database
    await Future.delayed(const Duration(milliseconds: 300));
    
    final exists = await MockUserDatabase.userExists(username);
    return !exists; // Return true if username is available (doesn't exist)
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

    // Check if username is already taken
    final isAvailable = await checkUsernameAvailability(username);
    if (!isAvailable) {
      return {
        'success': false,
        'error': 'ชื่อนี้ถูกใช้งานแล้ว',
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

    // Hash password
    final hashedPassword = hashPassword(password);

    // TODO: Call Rust backend API for registration
    // For now, save to mock database
    await Future.delayed(const Duration(milliseconds: 500));

    // Save user to database
    final success = await MockUserDatabase.addUser(username, hashedPassword);
    if (!success) {
      return {
        'success': false,
        'error': 'เกิดข้อผิดพลาดในการสมัครบัญชี',
      };
    }

    // Mock user data
    final userId = DateTime.now().millisecondsSinceEpoch.toString();

    // Save session
    await SessionManager.saveSession(
      userId: userId,
      username: username,
    );

    return {
      'success': true,
      'userId': userId,
      'username': username,
    };
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
