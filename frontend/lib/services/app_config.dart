import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

class AppConfig {
  static const String _defaultApiBaseUrl = 'http://localhost:3000';
  static const String _defaultWsUrl = 'ws://localhost:3000/ws';
  static const String _defaultStoragePublicBaseUrl =
      'https://qzmqoksvdgenoxdsrcql.supabase.co/storage/v1/object/public';
  static const String _defaultMobileWrapperBackgroundUrl =
      'https://i.pinimg.com/736x/fd/0d/45/fd0d45e403f966860c73fe08efd651d6.jpg';
  static const String _configFileName = 'app_config.json';

  static final _runtimeConfig = _loadRuntimeConfig();

  static String get apiBaseUrl {
    final fromEnv = Platform.environment['API_BASE_URL']?.trim() ?? '';
    if (fromEnv.isNotEmpty) return fromEnv;
    const fromDefine = String.fromEnvironment('API_BASE_URL', defaultValue: '');
    if (fromDefine.isNotEmpty) return fromDefine;
    if (_runtimeConfig.apiBaseUrl.isNotEmpty) return _runtimeConfig.apiBaseUrl;
    return _defaultApiBaseUrl;
  }

  static String get wsUrl {
    final fromEnv = Platform.environment['WS_URL']?.trim() ?? '';
    if (fromEnv.isNotEmpty) return fromEnv;
    const fromDefine = String.fromEnvironment('WS_URL', defaultValue: '');
    if (fromDefine.isNotEmpty) return fromDefine;
    if (_runtimeConfig.wsUrl.isNotEmpty) return _runtimeConfig.wsUrl;
    if (_runtimeConfig.apiBaseUrl.isNotEmpty) {
      final normalizedApi = _runtimeConfig.apiBaseUrl;
      if (normalizedApi.startsWith('https://')) {
        return '${normalizedApi.replaceFirst('https://', 'wss://')}/ws';
      }
      if (normalizedApi.startsWith('http://')) {
        return '${normalizedApi.replaceFirst('http://', 'ws://')}/ws';
      }
    }
    return _defaultWsUrl;
  }

  static String get storagePublicBaseUrl {
    const fromDefine =
        String.fromEnvironment('STORAGE_PUBLIC_BASE_URL', defaultValue: '');
    if (fromDefine.isNotEmpty) return fromDefine;
    if (_runtimeConfig.storagePublicBaseUrl.isNotEmpty) {
      return _runtimeConfig.storagePublicBaseUrl;
    }
    return _defaultStoragePublicBaseUrl;
  }

  /// Decorative background for [MobileWrapper] on desktop; override with
  /// `--dart-define=MOBILE_WRAPPER_BG_URL=...` or `MOBILE_WRAPPER_BG_URL` env.
  static String get mobileWrapperBackgroundUrl {
    final fromEnv = Platform.environment['MOBILE_WRAPPER_BG_URL']?.trim() ?? '';
    if (fromEnv.isNotEmpty) return fromEnv;
    const fromDefine =
        String.fromEnvironment('MOBILE_WRAPPER_BG_URL', defaultValue: '');
    if (fromDefine.isNotEmpty) return fromDefine;
    return _defaultMobileWrapperBackgroundUrl;
  }

  static _RuntimeConfig _loadRuntimeConfig() {
    if (kIsWeb) return const _RuntimeConfig.empty();
    try {
      final exePath = Platform.resolvedExecutable;
      final sep = Platform.pathSeparator;
      final exeDir = exePath.substring(0, exePath.lastIndexOf(sep));
      final configFile = File('$exeDir$sep$_configFileName');
      if (!configFile.existsSync()) return const _RuntimeConfig.empty();
      final raw = configFile.readAsStringSync().trim();
      if (raw.isEmpty) return const _RuntimeConfig.empty();
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return const _RuntimeConfig.empty();
      return _RuntimeConfig(
        apiBaseUrl: (decoded['apiBaseUrl'] as String? ?? '').trim(),
        wsUrl: (decoded['wsUrl'] as String? ?? '').trim(),
        storagePublicBaseUrl:
            (decoded['storagePublicBaseUrl'] as String? ?? '').trim(),
      );
    } catch (_) {
      return const _RuntimeConfig.empty();
    }
  }
}

class _RuntimeConfig {
  final String apiBaseUrl;
  final String wsUrl;
  final String storagePublicBaseUrl;

  const _RuntimeConfig({
    required this.apiBaseUrl,
    required this.wsUrl,
    required this.storagePublicBaseUrl,
  });

  const _RuntimeConfig.empty()
      : apiBaseUrl = '',
        wsUrl = '',
        storagePublicBaseUrl = '';
}

