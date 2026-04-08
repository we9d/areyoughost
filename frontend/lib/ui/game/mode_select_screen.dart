import 'dart:async';

import 'package:flutter/material.dart' as m;
import 'package:areyoughost/models/room_model.dart';
import 'package:areyoughost/services/session_manager.dart';
import 'package:areyoughost/services/network_service.dart';
import 'package:areyoughost/ui/game/game_screen.dart';
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
  StreamSubscription<GameEvent>? _networkSubscription;

  @override
  void initState() {
    super.initState();
    // Listen for RoomSyncEvent to navigate to the GameScreen
    _networkSubscription = NetworkService().events.listen((event) {
      if (event is RoomSyncEvent) {
        if (mounted) {
          setState(() => _loading = false);
          
          // Map RoomSyncEvent participants to RoomModel PlayerInfo
          final players = event.roomSync.participants.map((p) => PlayerInfo(
            playerId: p.playerId,
            username: p.username,
            isHost: p.seatNumber == 1, // Simple heuristic for now
            isOnline: p.isOnline,
            seatNumber: p.seatNumber,
          )).toList();

          final initialRoom = RoomModel(
            roomId: event.roomSync.roomId,
            players: players,
            maxPlayers: 16, // Default
            roomType: 'QUICK',
            status: 'WAITING',
            ownerId: players.isNotEmpty ? players.first.playerId : '',
          );

          m.Navigator.pushReplacement(
            context,
            m.MaterialPageRoute(
              builder: (_) => GameScreen(
                roomId: event.roomSync.roomId,
                initialRoom: initialRoom,
              ),
            ),
          );
        }
      }
    });
  }

  @override
  void dispose() {
    _networkSubscription?.cancel();
    super.dispose();
  }

  // Ensure WS is connected before sending any message.
  Future<void> _handleQuickPlay() async {
    if (_loading) return;

    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      if (!NetworkService().isConnected) {
        // Fallback or attempt reconnect? For now just error.
        setState(() {
          _loading = false;
          _errorMessage = 'ไม่ได้เชื่อมต่อกับเซิร์ฟเวอร์ กรุณาลองใหม่อีกครั้ง';
        });
        return;
      }

      await NetworkService().sendQuickJoinRequest();
      // We don't navigate yet, we wait for RoomSyncEvent in the listener above
    } catch (e) {
      setState(() {
        _loading = false;
        _errorMessage = 'เกิดข้อผิดพลาด: $e';
      });
    }
  }

  Future<void> _handlePlayWithFriend() async {
    setState(() { _errorMessage = 'ระบบสร้างห้องยังไม่พร้อมใช้งานในเวอร์ชันนี้'; });
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
