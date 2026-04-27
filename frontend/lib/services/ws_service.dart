import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:areyoughost/services/app_config.dart';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Singleton WebSocket client for Are You Ghost.
/// 
/// Usage:
///   await WsService.instance.connect(token);
///   WsService.instance.send('mm.join_queue', {});
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
  Timer? _handshakeTimeout;
  Timer? _connectionWatchdog;
  DateTime? _lastInboundAt;
  DateTime? _lastProbeAt;
  bool _awaitingProbeResponse = false;
  int _reconnectAttempt = 0;
  final Random _rand = Random();
  final List<Map<String, dynamic>> _pendingMessages = <Map<String, dynamic>>[];
  static const int _maxPendingMessages = 200;
  static const int _handshakeTimeoutSecs = 25;
  static const int _maxBackoffMs = 30000;
  static const int _watchdogCheckSecs = 2;
  static const int _watchdogStaleSecs = 7;
  static const int _watchdogProbeTimeoutSecs = 5;

  void _log(String message) {
    if (!kDebugMode) return;
    debugPrint('[WsService] $message');
  }

  // ── Connect ──────────────────────────────────────────────────

  Future<void> connect(String token) async {
    // Switching account/session token must drop stale resume token; otherwise
    // the server may resume the previous player identity.
    if (_authToken != null && _authToken != token) {
      _resumeToken = null;
      _pendingMessages.clear();
      _reconnectAttempt = 0;
    }
    _authToken = token;
    _manuallyDisconnected = false;
    _reconnectTimer?.cancel();
    _log('connect requested');
    connectionStatus.value = WsConnectionStatus.connecting;
    await _openSocket();
  }

  void _cancelHandshakeTimeout() {
    _handshakeTimeout?.cancel();
    _handshakeTimeout = null;
  }

  /// When the app returns from background or the OS regains connectivity,
  /// call this to either [syncRoom] if the socket is still up, or retry the
  /// handshake soon instead of waiting for the full exponential backoff.
  void nudgeReconnectIfDisconnected() {
    if (_manuallyDisconnected || _authToken == null || _authToken!.isEmpty) {
      return;
    }
    if (_connected) {
      syncRoom();
      return;
    }
    _scheduleReconnect(preferSoon: true);
  }

  Future<void> _openSocket() async {
    if (_connected || _channel != null) return;
    try {
      _channel = WebSocketChannel.connect(Uri.parse(AppConfig.wsUrl));
      _connected = true;
      _lastInboundAt = DateTime.now();
      _startConnectionWatchdog();
      _log('socket opened');
      connectionStatus.value = _reconnectAttempt > 0
          ? WsConnectionStatus.reconnecting
          : WsConnectionStatus.connecting;

      _cancelHandshakeTimeout();
      _handshakeTimeout = Timer(
        const Duration(seconds: _handshakeTimeoutSecs),
        () {
          if (!_manuallyDisconnected &&
              _connected &&
              connectionStatus.value != WsConnectionStatus.connected) {
            _log('handshake timeout, closing socket');
            unawaited(_channel?.sink.close());
          }
        },
      );

      // Try resume first if server previously issued a token.
      if (_resumeToken != null && _resumeToken!.isNotEmpty) {
        _log('trying session.resume');
        _rawSend({
          'type': 'session.resume',
          'payload': {'resumeToken': _resumeToken},
        });
      } else {
        final token = _authToken;
        if (token == null || token.isEmpty) {
          throw StateError('Missing auth token for websocket connect');
        }
        _log('sending auth.hello');
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
              if (msgType == 'error' && payload is Map<String, dynamic>) {
                final code = payload['code'] as String?;
                // Stale or consumed resume token would otherwise cause a reconnect loop.
                if (code == 'INVALID_RESUME' || code == 'INVALID_AUTH') {
                  _log('clearing resume token after $code');
                  _resumeToken = null;
                }
              }
              if (msgType == 'auth.ok' && payload is Map<String, dynamic>) {
                final rt = payload['resumeToken'];
                if (rt is String && rt.isNotEmpty) {
                  _resumeToken = rt;
                }
                _cancelHandshakeTimeout();
                connectionStatus.value = WsConnectionStatus.connected;
                _log('auth.ok received');
                _flushPendingMessages();
              }
              if (msgType == 'session.resumed') {
                _cancelHandshakeTimeout();
                connectionStatus.value = WsConnectionStatus.connected;
                _log('session.resumed received');
                _flushPendingMessages();
              }
              _controller.add(decoded);
              _lastInboundAt = DateTime.now();
              _awaitingProbeResponse = false;
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
    _log('socket closed');
    _cancelHandshakeTimeout();
    _stopConnectionWatchdog();
    _connected = false;
    _channel = null;
    if (connectionStatus.value != WsConnectionStatus.reconnecting) {
      connectionStatus.value = WsConnectionStatus.disconnected;
    }
    if (_manuallyDisconnected) return;
    _scheduleReconnect();
  }

  void _startConnectionWatchdog() {
    _stopConnectionWatchdog();
    _connectionWatchdog = Timer.periodic(
      const Duration(seconds: _watchdogCheckSecs),
      (_) {
        if (_manuallyDisconnected || !_connected) return;
        final lastInbound = _lastInboundAt;
        if (lastInbound == null) return;
        final staleFor = DateTime.now().difference(lastInbound);
        if (staleFor.inSeconds < _watchdogStaleSecs) return;

        if (!_awaitingProbeResponse) {
          _awaitingProbeResponse = true;
          _lastProbeAt = DateTime.now();
          _log('watchdog stale ${staleFor.inSeconds}s, probing room.sync');
          _rawSend({'type': 'room.sync', 'payload': {}});
          return;
        }

        final probeAt = _lastProbeAt;
        if (probeAt == null) return;
        final probeAge = DateTime.now().difference(probeAt);
        if (probeAge.inSeconds < _watchdogProbeTimeoutSecs) return;

        _log(
          'watchdog probe timeout (${probeAge.inSeconds}s), forcing reconnect',
        );
        connectionStatus.value = WsConnectionStatus.reconnecting;
        _connected = false;
        _stopConnectionWatchdog();
        unawaited(_channel?.sink.close());
      },
    );
  }

  void _stopConnectionWatchdog() {
    _connectionWatchdog?.cancel();
    _connectionWatchdog = null;
    _awaitingProbeResponse = false;
    _lastProbeAt = null;
  }

  void _scheduleReconnect({bool preferSoon = false}) {
    if (_manuallyDisconnected || _authToken == null || _authToken!.isEmpty) return;
    if (_reconnectTimer?.isActive == true && !preferSoon) return;
    if (preferSoon) {
      _reconnectTimer?.cancel();
    }
    connectionStatus.value = WsConnectionStatus.reconnecting;
    final baseMs = preferSoon
        ? 500
        : (1000 * (1 << _reconnectAttempt)).clamp(1000, _maxBackoffMs);
    final jitter = baseMs > 400 ? _rand.nextInt((baseMs ~/ 4).clamp(1, 8000)) : 0;
    final delayMs = (baseMs + jitter).clamp(250, _maxBackoffMs + 8000);
    _log('schedule reconnect in ${delayMs}ms (attempt=$_reconnectAttempt preferSoon=$preferSoon)');
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
      _log('queue message while disconnected: $type');
      _enqueuePending(msg);
      _scheduleReconnect();
      return;
    }
    _rawSend(msg);
  }

  void _rawSend(Map<String, dynamic> msg) {
    try {
      _channel?.sink.add(jsonEncode(msg));
    } catch (_) {
      _handleSocketClosed();
    }
  }

  void _enqueuePending(Map<String, dynamic> msg) {
    if (_pendingMessages.length >= _maxPendingMessages) {
      _pendingMessages.removeAt(0);
    }
    _pendingMessages.add(msg);
  }

  void _flushPendingMessages() {
    if (!_connected || _pendingMessages.isEmpty) return;
    _log('flush ${_pendingMessages.length} queued messages');
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

  Future<void> disconnect({bool clearSession = false}) async {
    _log('disconnect requested (clearSession=$clearSession)');
    _manuallyDisconnected = true;
    _cancelHandshakeTimeout();
    _stopConnectionWatchdog();
    _reconnectTimer?.cancel();
    await _channel?.sink.close();
    _connected = false;
    _channel = null;
    if (clearSession) {
      _authToken = null;
      _resumeToken = null;
      _pendingMessages.clear();
      _reconnectAttempt = 0;
    }
    connectionStatus.value = WsConnectionStatus.disconnected;
  }

  // ── Game Actions ─────────────────────────────────────────────

  void quickPlay() => send('mm.join_queue', {});

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
  void leaveQueue() => send('mm.leave_queue', {});

  void joinRoom(String roomId) => send('room.join', {'roomId': roomId});

  void syncRoom() => send('room.sync', {});
}

enum WsConnectionStatus {
  disconnected,
  connecting,
  reconnecting,
  connected,
}
