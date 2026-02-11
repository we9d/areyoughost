import 'package:flutter/material.dart';
import 'package:areyoughost/services/auth_service.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:bootstrap_icons/bootstrap_icons.dart';

/// Type of authentication text field
enum AuthFieldType {
  username,
  email,
  password,
  confirmPassword,
}

/// A custom text field widget for authentication forms.
/// 
/// Provides consistent styling, validation, and behavior across
/// login and registration screens.
class AuthTextField extends StatefulWidget {
  /// The type of field (username, email, password, etc.)
  final AuthFieldType fieldType;
  
  /// Text editing controller
  final TextEditingController controller;
  
  /// Optional hint text (if not provided, uses default based on fieldType)
  final String? hint;
  
  /// Optional icon (if not provided, uses default based on fieldType)
  final IconData? icon;
  
  /// Optional custom validator
  final String? Function(String?)? customValidator;

  const AuthTextField({
    super.key,
    required this.fieldType,
    required this.controller,
    this.hint,
    this.icon,
    this.customValidator,
  });

  @override
  State<AuthTextField> createState() => _AuthTextFieldState();
}

class _AuthTextFieldState extends State<AuthTextField> {
  bool _obscureText = true;

  /// Get default hint text based on field type
  String get _defaultHint {
    switch (widget.fieldType) {
      case AuthFieldType.username:
        return 'ชื่อผู้ใช้งาน';
      case AuthFieldType.email:
        return 'อีเมล';
      case AuthFieldType.password:
        return 'รหัสผ่าน';
      case AuthFieldType.confirmPassword:
        return 'ยืนยันรหัสผ่าน';
    }
  }

  /// Get default icon based on field type
  IconData get _defaultIcon {
    switch (widget.fieldType) {
      case AuthFieldType.username:
        return BootstrapIcons.person_circle;
      case AuthFieldType.email:
        return BootstrapIcons.envelope;
      case AuthFieldType.password:
      case AuthFieldType.confirmPassword:
        return PhosphorIcons.lockKey();
    }
  }

  /// Determine if field should be obscured
  bool get _shouldObscure {
    return (widget.fieldType == AuthFieldType.password ||
            widget.fieldType == AuthFieldType.confirmPassword) &&
        _obscureText;
  }

  /// Get validator function based on field type
  String? Function(String?) get _validator {
    if (widget.customValidator != null) {
      return widget.customValidator!;
    }

    switch (widget.fieldType) {
      case AuthFieldType.username:
        return AuthService.validateUsername;
      case AuthFieldType.password:
      case AuthFieldType.confirmPassword:
        return AuthService.validatePassword;
      case AuthFieldType.email:
        return _validateEmail;
    }
  }

  /// Email validation
  String? _validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'กรุณากรอกอีเมล';
    }
    final emailRegex = RegExp(
      r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
    );
    if (!emailRegex.hasMatch(value.trim())) {
      return 'กรุณากรอกอีเมลให้ถูกต้อง';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final isPasswordField = widget.fieldType == AuthFieldType.password ||
        widget.fieldType == AuthFieldType.confirmPassword;

    return SizedBox(
      width: 258,
      height: 70,
      child: TextFormField(
        controller: widget.controller,
        obscureText: _shouldObscure,
        cursorColor: Colors.black,
        cursorErrorColor: Colors.black,
        style: const TextStyle(
          fontFamily: 'Charmonman',
          fontSize: 18,
          color: Colors.black,
        ),
        validator: _validator,
        decoration: InputDecoration(
          hintText: widget.hint ?? _defaultHint,
          hintStyle: const TextStyle(
            fontFamily: 'Charmonman',
            fontSize: 18,
            color: Colors.black54,
          ),
          filled: true,
          fillColor: Colors.white,
          prefixIcon: Icon(
            widget.icon ?? _defaultIcon,
            color: Colors.black,
          ),
          // Password visibility toggle
          suffixIcon: isPasswordField
              ? IconButton(
                  icon: Icon(
                    _obscureText ? Icons.visibility_off : Icons.visibility,
                    color: Colors.black54,
                  ),
                  onPressed: () {
                    setState(() {
                      _obscureText = !_obscureText;
                    });
                  },
                )
              : null,
          contentPadding: const EdgeInsets.symmetric(vertical: 16),
          errorStyle: const TextStyle(
            fontFamily: 'Charmonman',
            fontSize: 12,
            color: Colors.white,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Colors.black, width: 2),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Colors.black, width: 2),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Colors.black, width: 2),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Colors.black, width: 2),
          ),
        ),
      ),
    );
  }
}
