import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:areyoughost/services/app_config.dart';
import 'package:areyoughost/services/session_manager.dart';
import 'package:areyoughost/services/ws_service.dart';
import 'package:areyoughost/src/rust/models.dart';

class AuthService {
  // Global auth state
  static final ValueNotifier<User?> currentUser = ValueNotifier<User?>(null);

  static String _friendlyErrorMessage(Object error) {
    final raw = error.toString();
    if (raw.contains('FormatException') || raw.contains('Unexpected end of input')) {
      return 'เซิร์ฟเวอร์ตอบกลับไม่ถูกต้อง กรุณาลองใหม่อีกครั้ง';
    }
    if (raw.contains('SocketException') || raw.contains('ClientException')) {
      return 'ไม่สามารถเชื่อมต่อเซิร์ฟเวอร์ได้';
    }
    return raw.replaceAll('Exception: ', '');
  }

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

      // Bring WS presence online as early as app startup so friends can see us online
      // without waiting for user to enter game mode screens.
      final token = session['token'] ?? '';
      if (token.isNotEmpty && !WsService.instance.isConnected) {
        try {
          await WsService.instance.connect(token);
          await WsService.instance.waitForAny(
            {'auth.ok', 'session.resumed'},
            timeout: const Duration(seconds: 5),
          );
        } catch (_) {
          // Ignore startup WS errors: app can still function and reconnect later.
        }
      }
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

    try {
      final response = await http.post(
        Uri.parse('${AppConfig.apiBaseUrl}/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': username,
          'password': password, // The server handles hashing
        }),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        // Login successful
        final userId = data['player']['id'];
        final uname = data['player']['username'];
        final token = data['accessToken'];

        // ปิด WS เก่า (และล้าง resume token) ก่อนเปลี่ยน session — ไม่งั้น room.create_private ยังใช้ตัวตนผู้ใช้เก่า
        await WsService.instance.disconnect(clearSession: true);

        // Save session
        await SessionManager.saveSession(userId: userId, username: uname, token: token);
        
        // Store Token (optional: expand SessionManager to hold JWT)
        // await SessionManager.saveToken(token);

        // Update state
        currentUser.value = User(
          userId: userId,
          username: uname,
          passwordHash: '',
          createdAt: '',
          lastLogin: null,
        );

        // Connect immediately after login so online status appears right away.
        if (token is String && token.isNotEmpty) {
          try {
            await WsService.instance.connect(token);
            await WsService.instance.waitForAny(
              {'auth.ok', 'session.resumed'},
              timeout: const Duration(seconds: 5),
            );
          } catch (_) {}
        }

        return {'success': true, 'userId': userId, 'username': uname, 'token': token};
      } else {
        return {'success': false, 'error': data['error'] ?? 'Login failed'};
      }
    } catch (e) {
      return {'success': false, 'error': 'Cannot connect to server'};
    }
  }

  // Register function
  static Future<Map<String, dynamic>> register({
    required String username,
    required String email,
    required String password,
  }) async {
    // Validate username
    final usernameError = validateUsername(username);
    if (usernameError != null) {
      return {'success': false, 'error': usernameError};
    }

    // Validate email
    if (email.trim().isEmpty) {
        return {'success': false, 'error': 'กรุณากรอกอีเมล'};
    }

    // Validate password
    final passwordError = validatePassword(password);
    if (passwordError != null) {
      return {'success': false, 'error': passwordError};
    }

    try {
      final response = await http.post(
        Uri.parse('${AppConfig.apiBaseUrl}/auth/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': username,
          'email': email,
          'password': password, // The server handles hashing
        }),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 201) {
        // Register successful
        final userId = data['player']['id'];
        final uname = data['player']['username'];

        await WsService.instance.disconnect(clearSession: true);

        // Save session
        await SessionManager.saveSession(userId: userId, username: uname);

        // Update state
        currentUser.value = User(
          userId: userId,
          username: uname,
          passwordHash: '',
          createdAt: '',
          lastLogin: null,
        );

        return {'success': true, 'userId': userId, 'username': uname};
      } else {
        return {'success': false, 'error': data['error'] ?? 'Registration failed'};
      }
    } catch (e) {
      return {'success': false, 'error': 'Cannot connect to server'};
    }
  }

  // Logout function
  static Future<void> logout() async {
    await WsService.instance.disconnect(clearSession: true);
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
      final response = await http.post(
        Uri.parse('${AppConfig.apiBaseUrl}/auth/update-username'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': user.userId,
          'new_username': newUsername,
        }),
      );

      Map<String, dynamic> data = const {};
      if (response.body.isNotEmpty) {
        try {
          data = jsonDecode(response.body) as Map<String, dynamic>;
        } catch (_) {
          data = const {};
        }
      }
      if (response.statusCode != 200) {
        final serverError = data['error'];
        if (serverError is String && serverError.isNotEmpty) {
          return {'success': false, 'error': serverError};
        }
        return {
          'success': false,
          'error': 'เปลี่ยนชื่อไม่สำเร็จ (HTTP ${response.statusCode})',
        };
      }

      // Update session and state
      await SessionManager.saveSession(
        userId: user.userId,
        username: newUsername,
        token: (await SessionManager.getSession())?['token'],
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
      return {'success': false, 'error': _friendlyErrorMessage(e)};
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
