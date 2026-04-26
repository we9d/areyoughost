import 'dart:async';

import 'package:flutter/material.dart';
import 'package:areyoughost/models/room_model.dart';
import 'package:areyoughost/services/ws_service.dart';
import 'package:areyoughost/services/auth_service.dart';
import 'package:areyoughost/ui/Invite_friend/invite_panel.dart';

/// Waiting Room — shown after joining/creating any room.
/// 
/// source of truth: room.state from server
/// supplemental toasts: room.player_joined / room.player_left
class WaitingRoomScreen extends StatefulWidget {
  final RoomModel initialRoom;
  final bool isHost;

  const WaitingRoomScreen({
    super.key,
    required this.initialRoom,
    required this.isHost,
  });

  @override
  State<WaitingRoomScreen> createState() => _WaitingRoomScreenState();
}

class _WaitingRoomScreenState extends State<WaitingRoomScreen> {
  late RoomModel _room;
  StreamSubscription<Map<String, dynamic>>? _sub;
  String? _toastMessage;
  Timer? _toastTimer;

  @override
  void initState() {
    super.initState();
    _room = widget.initialRoom;
    _sub = WsService.instance.stream.listen(_onServerMessage);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _toastTimer?.cancel();
    super.dispose();
  }

  void _onServerMessage(Map<String, dynamic> msg) {
    final type = msg['type'] as String?;
    if (type == null) return;

    switch (type) {
      case 'room.state':
        final payload = msg['payload'] as Map<String, dynamic>?;
        if (payload != null) {
          setState(() => _room = RoomModel.fromJson(payload));
        }
        break;

      case 'room.player_joined':
        final p = msg['payload'];
        final name = p?['username'] as String? ?? 'Someone';
        _showToast('$name เข้าร่วมห้อง');
        break;

      case 'room.player_left':
        final p = msg['payload'];
        final name = p?['username'] as String? ?? 'Someone';
        _showToast('$name ออกจากห้อง');
        break;

      case 'invite.received':
        // Handled globally in the app — nothing to do here
        break;
    }
  }

  void _showToast(String message) {
    setState(() => _toastMessage = message);
    _toastTimer?.cancel();
    _toastTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _toastMessage = null);
    });
  }

  void _handleLeave() {
    WsService.instance.leaveRoom();
    Navigator.pop(context);
  }

  void _handleOpenInvite() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => InvitePanel(
        inviteCode: _room.inviteCode ?? '',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final myId = AuthService.currentUser.value?.userId ?? '';
    final isHost = widget.isHost ||
        _room.players.any((p) => p.playerId == myId && p.isHost);

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      body: Stack(
        children: [
          // Background
          Positioned.fill(
            child: Image.asset(
              'assets/images/RandomRoleBg.jpg',
              fit: BoxFit.cover,
              color: Colors.black.withOpacity(0.6),
              colorBlendMode: BlendMode.darken,
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
                        onPressed: _handleLeave,
                      ),
                      const Expanded(
                        child: Text(
                          'ห้องรอ',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontFamily: 'Charmonman',
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      // Player count badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${_room.players.length}/${_room.maxPlayers}',
                          style: const TextStyle(color: Colors.white, fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                ),

                // รหัสชวนแสดงเฉพาะโฮสต์ (ผู้รับคำเชิญเข้าผ่านกล่องคำเชิญได้โดยไม่ต้องเห็นรหัส)
                if (isHost && _room.inviteCode != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: Column(
                        children: [
                          const Text(
                            'รหัสชวน',
                            style: TextStyle(color: Colors.white54, fontSize: 12),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _room.inviteCode!,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 8,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                const SizedBox(height: 16),

                // Player List
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _room.players.length,
                    itemBuilder: (ctx, i) {
                      final player = _room.players[i];
                      return _PlayerTile(player: player, myId: myId);
                    },
                  ),
                ),

                // Empty state
                if (_room.players.isEmpty)
                  const Expanded(
                    child: Center(
                      child: Text(
                        'รอผู้เล่นเข้าร่วม...',
                        style: TextStyle(color: Colors.white54, fontSize: 16),
                      ),
                    ),
                  ),

                // Bottom Actions
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      if (isHost) ...[
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _handleOpenInvite,
                            icon: const Icon(Icons.person_add),
                            label: const Text('ชวนเพื่อน'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white.withOpacity(0.15),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: const BorderSide(color: Colors.white24),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _room.players.length >= 2
                                ? () {
                                    // TODO: send game.start when ready
                                  }
                                : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF7C3AED),
                              disabledBackgroundColor: Colors.white12,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Text(
                              _room.players.length >= 2
                                  ? 'เริ่มเกม (${_room.players.length} คน)'
                                  : 'รอผู้เล่นอย่างน้อย 2 คน',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ] else
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            onPressed: _handleLeave,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: const BorderSide(color: Colors.white30),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text('ออกจากห้อง'),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Toast
          if (_toastMessage != null)
            Positioned(
              bottom: 100,
              left: 20,
              right: 20,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Text(
                  _toastMessage!,
                  style: const TextStyle(
                    color: Colors.black87,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PlayerTile extends StatelessWidget {
  final PlayerInfo player;
  final String myId;

  const _PlayerTile({required this.player, required this.myId});

  @override
  Widget build(BuildContext context) {
    final isMe = player.playerId == myId;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isMe
            ? Colors.white.withOpacity(0.12)
            : Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
        border: isMe
            ? Border.all(color: const Color(0xFF7C3AED).withOpacity(0.6))
            : Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: Colors.white.withOpacity(0.15),
            child: Text(
              player.username.isNotEmpty
                  ? player.username[0].toUpperCase()
                  : '?',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              '${player.username}${isMe ? ' (คุณ)' : ''}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (player.isHost)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF7C3AED).withOpacity(0.3),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFF7C3AED)),
              ),
              child: const Text(
                'Host',
                style: TextStyle(
                  color: Color(0xFFBB86FC),
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
