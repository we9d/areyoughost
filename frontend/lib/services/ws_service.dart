import 'dart:async';
import 'dart:convert';
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

  static const String _wsUrl = 'ws://localhost:3000/ws';

  WebSocketChannel? _channel;
  final _controller = StreamController<Map<String, dynamic>>.broadcast();

  /// Broadcast stream of all decoded server messages.
  Stream<Map<String, dynamic>> get stream => _controller.stream;

  bool _connected = false;
  bool get isConnected => _connected;

  // ── Connect ──────────────────────────────────────────────────

  Future<void> connect(String token) async {
    if (_connected) return;
    try {
      _channel = WebSocketChannel.connect(Uri.parse(_wsUrl));
      _connected = true;

      // Authenticate immediately
      _rawSend({'type': 'auth.hello', 'payload': {'token': token}});

      _channel!.stream.listen(
        (raw) {
          if (raw is String) {
            try {
              final decoded = jsonDecode(raw) as Map<String, dynamic>;
              _controller.add(decoded);
            } catch (_) {}
          }
        },
        onDone: () {
          _connected = false;
        },
        onError: (_) {
          _connected = false;
        },
      );
    } catch (e) {
      _connected = false;
      rethrow;
    }
  }

  /// Send a WS message to the server.
  void send(String type, Map<String, dynamic> payload) {
    if (!_connected) return;
    _rawSend({'type': type, 'payload': payload});
  }

  void _rawSend(Map<String, dynamic> msg) {
    _channel?.sink.add(jsonEncode(msg));
  }

  /// Convenience: wait for the next message of a given type.
  Future<Map<String, dynamic>> waitFor(String type, {Duration timeout = const Duration(seconds: 10)}) {
    return stream
        .where((m) => m['type'] == type)
        .first
        .timeout(timeout);
  }

  // ── Disconnect ───────────────────────────────────────────────

  Future<void> disconnect() async {
    await _channel?.sink.close();
    _connected = false;
  }

  // ── Game Actions ─────────────────────────────────────────────

  void quickPlay() => send('mm.quick_play', {});

  void createPrivateRoom() => send('room.create_private', {});

  void sendInvite(String friendId, String inviteCode) =>
      send('invite.send', {'friendId': friendId, 'inviteCode': inviteCode});

  void acceptInvite(String inviteCode) =>
      send('invite.accept', {'inviteCode': inviteCode});

  void leaveRoom() => send('room.leave', {});
}
