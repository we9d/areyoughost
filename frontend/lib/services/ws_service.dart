import 'dart:async';
import 'dart:convert';
import 'package:areyoughost/services/app_config.dart';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Singleton WebSocket client for Are You Ghost.
/// 
/// Usage:
///   await WsService.instance.connect(token);
///   WsService.instance.send('mm.quick_play', {});
///   WsService.instance.stream.listen((msg) { ... });
class WsService {
  WsService._();
  static final WsService instance = WsService._();

  WebSocketChannel? _channel;
  final _controller = StreamController<Map<String, dynamic>>.broadcast();
  final ValueNotifier<WsConnectionStatus> connectionStatus =
      ValueNotifier<WsConnectionStatus>(WsConnectionStatus.disconnected);

  /// Broadcast stream of all decoded server messages.
  Stream<Map<String, dynamic>> get stream => _controller.stream;

  bool _connected = false;
  bool get isConnected => _connected;
  bool _manuallyDisconnected = false;
  String? _authToken;
  String? _resumeToken;
  Timer? _reconnectTimer;
  int _reconnectAttempt = 0;
  final List<Map<String, dynamic>> _pendingMessages = <Map<String, dynamic>>[];
  static const int _maxPendingMessages = 200;

  // ── Connect ──────────────────────────────────────────────────

  Future<void> connect(String token) async {
    _authToken = token;
    _manuallyDisconnected = false;
    _reconnectTimer?.cancel();
    connectionStatus.value = WsConnectionStatus.connecting;
    await _openSocket();
  }

  Future<void> _openSocket() async {
    if (_connected || _channel != null) return;
    try {
      _channel = WebSocketChannel.connect(Uri.parse(AppConfig.wsUrl));
      _connected = true;
      connectionStatus.value = _reconnectAttempt > 0
          ? WsConnectionStatus.reconnecting
          : WsConnectionStatus.connecting;

      // Try resume first if server previously issued a token.
      if (_resumeToken != null && _resumeToken!.isNotEmpty) {
        _rawSend({
          'type': 'session.resume',
          'payload': {'resumeToken': _resumeToken},
        });
      } else {
        final token = _authToken;
        if (token == null || token.isEmpty) {
          throw StateError('Missing auth token for websocket connect');
        }
        _rawSend({
          'type': 'auth.hello',
          'payload': {'token': token},
        });
      }

      _channel!.stream.listen(
        (raw) {
          if (raw is String) {
            try {
              final decoded = jsonDecode(raw) as Map<String, dynamic>;
              final msgType = decoded['type'] as String?;
              final payload = decoded['payload'];
              if (msgType == 'auth.ok' && payload is Map<String, dynamic>) {
                final rt = payload['resumeToken'];
                if (rt is String && rt.isNotEmpty) {
                  _resumeToken = rt;
                }
                connectionStatus.value = WsConnectionStatus.connected;
                _flushPendingMessages();
              }
              if (msgType == 'session.resumed') {
                connectionStatus.value = WsConnectionStatus.connected;
                _flushPendingMessages();
              }
              _controller.add(decoded);
            } catch (_) {}
          }
        },
        onDone: _handleSocketClosed,
        onError: (_) => _handleSocketClosed(),
      );
    } catch (e) {
      _connected = false;
      _scheduleReconnect();
      rethrow;
    }
  }

  void _handleSocketClosed() {
    _connected = false;
    _channel = null;
    if (connectionStatus.value != WsConnectionStatus.reconnecting) {
      connectionStatus.value = WsConnectionStatus.disconnected;
    }
    if (_manuallyDisconnected) return;
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_manuallyDisconnected || _authToken == null || _authToken!.isEmpty) return;
    if (_reconnectTimer?.isActive == true) return;
    connectionStatus.value = WsConnectionStatus.reconnecting;
    final delayMs = (1000 * (1 << _reconnectAttempt)).clamp(1000, 10000);
    _reconnectTimer = Timer(Duration(milliseconds: delayMs), () async {
      if (_manuallyDisconnected) return;
      _reconnectAttempt = (_reconnectAttempt + 1).clamp(0, 10);
      try {
        await _openSocket();
        // Reset only after auth.ok/session.resumed to avoid false positive.
      } catch (_) {
        _scheduleReconnect();
      }
    });
  }

  /// Send a WS message to the server.
  void send(String type, Map<String, dynamic> payload) {
    final msg = {'type': type, 'payload': payload};
    if (!_connected) {
      _enqueuePending(msg);
      _scheduleReconnect();
      return;
    }
    _rawSend(msg);
  }

  void _rawSend(Map<String, dynamic> msg) {
    _channel?.sink.add(jsonEncode(msg));
  }

  void _enqueuePending(Map<String, dynamic> msg) {
    if (_pendingMessages.length >= _maxPendingMessages) {
      _pendingMessages.removeAt(0);
    }
    _pendingMessages.add(msg);
  }

  void _flushPendingMessages() {
    if (!_connected || _pendingMessages.isEmpty) return;
    final snapshot = List<Map<String, dynamic>>.from(_pendingMessages);
    _pendingMessages.clear();
    for (final msg in snapshot) {
      _rawSend(msg);
    }
    _reconnectAttempt = 0;
  }

  /// Convenience: wait for the next message of a given type.
  Future<Map<String, dynamic>> waitFor(String type, {Duration timeout = const Duration(seconds: 10)}) {
    return stream
        .where((m) => m['type'] == type)
        .first
        .timeout(timeout);
  }

  /// Wait until one of [types] arrives (e.g. `room.joined` or `error`).
  ///
  /// Subscribe **before** sending the request that triggers the reply, to avoid
  /// missing a fast `room.joined` on localhost.
  Future<Map<String, dynamic>> waitForAny(
    Set<String> types, {
    Duration timeout = const Duration(seconds: 10),
  }) {
    return stream
        .where((m) => types.contains(m['type'] as String?))
        .first
        .timeout(timeout);
  }

  // ── Disconnect ───────────────────────────────────────────────

  Future<void> disconnect() async {
    _manuallyDisconnected = true;
    _reconnectTimer?.cancel();
    await _channel?.sink.close();
    _connected = false;
    _channel = null;
    connectionStatus.value = WsConnectionStatus.disconnected;
  }

  // ── Game Actions ─────────────────────────────────────────────

  void quickPlay() => send('mm.quick_play', {});

  void createPrivateRoom() => send('room.create_private', {});

  void sendInvite(String friendId, String inviteCode) =>
      send('invite.send', {'friendId': friendId, 'inviteCode': inviteCode});

  /// Send invite and await either success or error response.
  Future<Map<String, dynamic>> sendInviteAndWait(
    String friendId,
    String inviteCode, {
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final future = waitForAny({'invite.sent', 'error'}, timeout: timeout);
    sendInvite(friendId, inviteCode);
    return future;
  }

  void acceptInvite(String inviteCode) =>
      send('invite.accept', {'inviteCode': inviteCode});

  void leaveRoom() => send('room.leave', {});
}

enum WsConnectionStatus {
  disconnected,
  connecting,
  reconnecting,
  connected,
}
