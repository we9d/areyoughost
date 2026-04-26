import 'dart:async';

import 'package:flutter/material.dart' as m;
import 'package:areyoughost/models/room_model.dart';
import 'package:areyoughost/services/ws_service.dart';
import 'package:areyoughost/services/session_manager.dart';
import 'package:areyoughost/ui/Invite_friend/Invite_host.dart';
import 'package:areyoughost/ui/game/game_pre_lobby_screen.dart';
import 'package:areyoughost/ui/widgets/buttons/playnow_button.dart';
import 'package:areyoughost/ui/widgets/buttons/playtogether_button.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

class ModeSelectScreen extends m.StatefulWidget {
  const ModeSelectScreen({super.key});

  @override
  m.State<ModeSelectScreen> createState() => _ModeSelectScreenState();
}

class _ModeSelectScreenState extends m.State<ModeSelectScreen> {
  bool _loading = false;
  String? _errorMessage;

  // Ensure WS is connected before sending any message.
  Future<bool> _ensureConnected() async {
    if (WsService.instance.isConnected) return true;
    final session = await SessionManager.getSession();
    final token = session?['token'];
    if (token == null || token.isEmpty) {
      setState(() => _errorMessage = 'กรุณาเข้าสู่ระบบก่อน');
      return false;
    }
    try {
      await WsService.instance.connect(token);
      // Accept both fresh auth and resumed session.
      await WsService.instance.waitForAny(
        {'auth.ok', 'session.resumed'},
        timeout: const Duration(seconds: 5),
      );
      return true;
    } catch (_) {
      setState(() => _errorMessage = 'ไม่สามารถเชื่อมต่อ server ได้');
      return false;
    }
  }

  // ── Quick Play ────────────────────────────────────────────────

  Future<void> _handleQuickPlay() async {
    setState(() {_loading = true; _errorMessage = null;});

    if (!await _ensureConnected()) {
      setState(() => _loading = false);
      return;
    }

    WsService.instance.quickPlay();

    try {
      final expireAt = DateTime.now().add(const Duration(seconds: 30));
      while (DateTime.now().isBefore(expireAt)) {
        final remaining = expireAt.difference(DateTime.now());
        final msg = await WsService.instance.waitForAny(
          {'mm.queued', 'mm.matched', 'room.joined', 'room.state', 'error'},
          timeout: remaining.inSeconds > 0 ? remaining : const Duration(seconds: 1),
        );

        final type = msg['type'] as String?;
        if (type == 'error') {
          final payload = msg['payload'];
          final code = payload is Map ? payload['code'] as String? : null;
          final detail = payload is Map ? payload['message'] as String? : null;
          if (!mounted) return;
          setState(() {
            _loading = false;
            _errorMessage = _quickPlayErrorMessage(code, detail);
          });
          return;
        }

        if (type == 'mm.queued') {
          if (!mounted) return;
          setState(() {
            _errorMessage = 'กำลังค้นหาห้อง...';
          });
          continue;
        }

        if (type == 'mm.matched') {
          // wait for room.state/room.joined payload in next message
          continue;
        }

        if (type == 'room.joined' || type == 'room.state') {
          final payload = msg['payload'];
          final roomJson = (payload is Map<String, dynamic> &&
                  payload['room'] is Map<String, dynamic>)
              ? payload['room'] as Map<String, dynamic>
              : (payload as Map<String, dynamic>? ?? <String, dynamic>{});
          final quickplayDeadlineUnix = (payload is Map<String, dynamic>
                  ? payload['quickplayDeadlineUnix'] as int?
                  : null) ??
              (roomJson['quickplayDeadlineUnix'] as int?);
          if (roomJson.isEmpty) continue;
          final room = RoomModel.fromJson(roomJson);
          if (!mounted) return;
          setState(() => _loading = false);
          m.Navigator.pushReplacement(
            context,
            m.MaterialPageRoute(
              builder: (_) => GamePreLobbyScreen(
                initialRoom: room,
                isHost: false,
                initialQuickplayDeadlineUnix: quickplayDeadlineUnix,
              ),
            ),
          );
          return;
        }
      }
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = 'ยังไม่พบผู้เล่นพอสำหรับเล่นทันที ลองใหม่อีกครั้ง';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = 'ยังไม่พบผู้เล่นพอสำหรับเล่นทันที ลองใหม่อีกครั้ง';
      });
    }
  }

  String _quickPlayErrorMessage(String? code, String? detail) {
    if (code == 'QUICK_PLAY_FAILED') {
      return detail?.isNotEmpty == true
          ? 'เล่นทันทีไม่สำเร็จ: $detail'
          : 'เล่นทันทีไม่สำเร็จ (เช่น ฐานข้อมูลหรือเซิร์ฟเวอร์)';
    }
    return 'เล่นทันทีไม่สำเร็จ ลองใหม่อีกครั้ง';
  }

  // ── Play with Friend ──────────────────────────────────────────

  Future<void> _handlePlayWithFriend() async {
    setState(() {_loading = true; _errorMessage = null;});

    if (!await _ensureConnected()) {
      setState(() => _loading = false);
      return;
    }

    final replyFuture = WsService.instance.waitForAny(
      {'room.created', 'error'},
      timeout: const Duration(seconds: 10),
    );
    WsService.instance.createPrivateRoom();

    try {
      final msg = await replyFuture;
      if (msg['type'] == 'error') {
        final payload = msg['payload'];
        final code = payload is Map ? payload['code'] as String? : null;
        final detail = payload is Map ? payload['message'] as String? : null;
        if (!mounted) return;
        setState(() {
          _loading = false;
          _errorMessage = code == 'CREATE_PRIVATE_FAILED' && detail?.isNotEmpty == true
              ? 'สร้างห้องไม่สำเร็จ: $detail'
              : 'สร้างห้องไม่สำเร็จ ลองใหม่อีกครั้ง';
        });
        return;
      }

      final room = RoomModel.fromJson(
          (msg['payload']['room'] as Map<String, dynamic>?) ?? msg['payload']);

      if (!mounted) return;
      setState(() => _loading = false);
      m.Navigator.pushReplacement(
        context,
        m.MaterialPageRoute(
          builder: (_) => HostRoomScreen(initialRoom: room),
        ),
      );
    } catch (_) {
      setState(() {
        _loading = false;
        _errorMessage = 'สร้างห้องไม่สำเร็จ ลองใหม่อีกครั้ง';
      });
    }
  }

  @override
  m.Widget build(m.BuildContext context) {
    return m.Scaffold(
      body: m.Stack(
        children: [
          m.Positioned.fill(
            child: m.Image.asset(
              'assets/images/ModeSelectBg.jpg',
              fit: m.BoxFit.cover,
            ),
          ),
          m.Positioned.fill(
            child: m.Container(color: m.Colors.black.withOpacity(0.55)),
          ),
          m.SafeArea(
            child: m.Column(
              children: [
                m.Padding(
                  padding: const m.EdgeInsets.only(top: 24, left: 6),
                  child: m.Align(
                    alignment: m.Alignment.centerLeft,
                    child: m.IconButton(
                      icon: m.Icon(
                        PhosphorIcons.caretLeft(),
                        size: 32,
                        color: m.Colors.white,
                      ),
                      splashRadius: 20,
                      onPressed: _loading ? null : () => m.Navigator.pop(context),
                    ),
                  ),
                ),
                const m.Spacer(),
                const m.Text(
                  'เลือกโหมด',
                  style: m.TextStyle(
                    fontSize: 32,
                    fontWeight: m.FontWeight.w700,
                    color: m.Colors.white,
                    shadows: [
                      m.Shadow(blurRadius: 6, color: m.Colors.black87, offset: m.Offset(0, 2)),
                    ],
                  ),
                ),
                const m.SizedBox(height: 36),
                if (_loading)
                  const m.CircularProgressIndicator(color: m.Colors.white)
                else ...[
                  PlaynowButton(onPressed: _handleQuickPlay),
                  const m.SizedBox(height: 18),
                  PlaytogetherButton(onPressed: _handlePlayWithFriend),
                ],
                if (_errorMessage != null) ...[
                  const m.SizedBox(height: 16),
                  m.Padding(
                    padding: const m.EdgeInsets.symmetric(horizontal: 32),
                    child: m.Text(
                      _errorMessage!,
                      style: const m.TextStyle(
                        color: m.Colors.redAccent,
                        fontSize: 14,
                        fontFamily: 'Charmonman',
                      ),
                      textAlign: m.TextAlign.center,
                    ),
                  ),
                ],
                const m.Spacer(flex: 2),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
