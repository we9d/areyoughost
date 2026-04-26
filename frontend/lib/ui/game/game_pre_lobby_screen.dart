import 'dart:async';

import 'package:areyoughost/models/mock_models.dart';
import 'package:areyoughost/models/room_model.dart';
import 'package:areyoughost/services/auth_service.dart';
import 'package:areyoughost/services/ws_service.dart';
import 'package:areyoughost/ui/Invite_friend/invite_friends_dialog.dart';
import 'package:areyoughost/ui/game/random_role_screen.dart';
import 'package:areyoughost/ui/game/widgets/player_grid_day.dart';
import 'package:areyoughost/ui/widgets/buttons/Invite_chat.dart';
import 'package:areyoughost/ui/widgets/buttons/roles_buttons.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

/// ห้องรอก่อนเริ่มสุ่มบทบาท — แสดงกริดที่นั่ง + แชท (รูปแบบใกล้หน้าเกมกลางวัน)
class GamePreLobbyScreen extends StatefulWidget {
  final RoomModel initialRoom;
  final bool isHost;
  final int? initialQuickplayDeadlineUnix;

  const GamePreLobbyScreen({
    super.key,
    required this.initialRoom,
    required this.isHost,
    this.initialQuickplayDeadlineUnix,
  });

  @override
  State<GamePreLobbyScreen> createState() => _GamePreLobbyScreenState();
}

class _GamePreLobbyScreenState extends State<GamePreLobbyScreen> {
  late RoomModel _room;
  StreamSubscription<Map<String, dynamic>>? _sub;
  Timer? _countdownTimer;
  final ScrollController _feedScrollController = ScrollController();
  final TextEditingController _chatController = TextEditingController();
  final List<_RoomFeedEntry> _messages = <_RoomFeedEntry>[];
  int? _quickplayCountdown;
  bool _navigated = false;
  final Set<String> _knownPlayerIds = <String>{};
  final Map<String, int> _joinOrderByPlayerId = <String, int>{};
  final Map<String, int> _joinOrderByUsername = <String, int>{};
  int _nextJoinOrder = 1;

  @override
  void initState() {
    super.initState();
    _room = widget.initialRoom;
    _knownPlayerIds.addAll(_room.players.map((p) => p.playerId));
    _seedInitialJoinFeed();
    _sub = WsService.instance.stream.listen(_onServerMessage);
    WsService.instance.syncRoom();
    final initialDeadline = widget.initialQuickplayDeadlineUnix;
    if (initialDeadline != null) {
      _startCountdownFromDeadline(initialDeadline);
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _countdownTimer?.cancel();
    _feedScrollController.dispose();
    _chatController.dispose();
    super.dispose();
  }

  void _startCountdownFromDeadline(int deadlineUnix) {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final remaining = (deadlineUnix - now).clamp(0, 30).toInt();
    _startCountdown(remaining);
  }

  void _startCountdown(int seconds) {
    _countdownTimer?.cancel();
    setState(() => _quickplayCountdown = seconds);
    if (seconds <= 0) return;
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _navigated) {
        timer.cancel();
        return;
      }
      final current = _quickplayCountdown ?? 0;
      if (current <= 1) {
        timer.cancel();
        setState(() => _quickplayCountdown = 0);
      } else {
        setState(() => _quickplayCountdown = current - 1);
      }
    });
  }

  void _onServerMessage(Map<String, dynamic> msg) {
    final type = msg['type'] as String?;
    if (type == null) return;
    switch (type) {
      case 'room.state':
        final payload = msg['payload'] as Map<String, dynamic>?;
        if (payload != null && mounted) {
          final nextRoom = RoomModel.fromJson(payload);
          final deadlineUnix = payload['quickplayDeadlineUnix'];
          if (deadlineUnix is int) {
            _startCountdownFromDeadline(deadlineUnix);
          }
          _syncMembershipFeedFromState(nextRoom);
          setState(() => _room = nextRoom);
        }
        break;
      case 'room.player_joined':
        final p = msg['payload'] as Map<String, dynamic>? ?? <String, dynamic>{};
        final playerId = (p['playerId'] as String?) ?? '';
        final username = (p['username'] as String?) ?? 'เพื่อน';
        if (playerId.isNotEmpty) _knownPlayerIds.add(playerId);
        _appendChatMessage(
          playerId: playerId,
          senderName: username,
          content: 'เข้าร่วม',
          kind: _FeedKind.joined,
        );
        break;
      case 'room.player_left':
        final p = msg['payload'] as Map<String, dynamic>? ?? <String, dynamic>{};
        final playerId = (p['playerId'] as String?) ?? '';
        final username = (p['username'] as String?) ?? 'เพื่อน';
        _appendChatMessage(
          playerId: playerId,
          senderName: username,
          content: 'ออกจากห้อง',
          kind: _FeedKind.left,
        );
        if (playerId.isNotEmpty) _knownPlayerIds.remove(playerId);
        break;
      case 'mm.countdown':
        final payload = msg['payload'] as Map<String, dynamic>? ?? <String, dynamic>{};
        final seconds = payload['seconds'];
        final deadlineUnix = payload['deadlineUnix'];
        if (deadlineUnix is int) {
          _startCountdownFromDeadline(deadlineUnix);
        } else if (seconds is int) {
          _startCountdown(seconds);
        }
        break;
      case 'mm.countdown_cancelled':
        _countdownTimer?.cancel();
        if (mounted) setState(() => _quickplayCountdown = null);
        break;
      case 'game.started':
        final payload = msg['payload'] as Map<String, dynamic>? ?? <String, dynamic>{};
        _goRandomRole(startPayload: payload);
        break;
    }
  }

  void _seedInitialJoinFeed() {
    for (final player in _room.players) {
      _appendChatMessage(
        playerId: player.playerId,
        senderName: player.username,
        content: 'เข้าร่วม',
        kind: _FeedKind.joined,
      );
    }
  }

  void _syncMembershipFeedFromState(RoomModel nextRoom) {
    final nextById = <String, PlayerInfo>{
      for (final p in nextRoom.players) p.playerId: p,
    };
    for (final entry in nextById.entries) {
      if (!_knownPlayerIds.contains(entry.key)) {
        _knownPlayerIds.add(entry.key);
        _appendChatMessage(
          playerId: entry.key,
          senderName: entry.value.username,
          content: 'เข้าร่วม',
          kind: _FeedKind.joined,
        );
      }
    }
    final removed = _knownPlayerIds.where((id) => !nextById.containsKey(id)).toList();
    if (removed.isEmpty) return;
    final prevById = <String, PlayerInfo>{for (final p in _room.players) p.playerId: p};
    for (final id in removed) {
      final username = prevById[id]?.username ?? 'ผู้เล่น';
      _appendChatMessage(
        playerId: id,
        senderName: username,
        content: 'ออกจากห้อง',
        kind: _FeedKind.left,
      );
      _knownPlayerIds.remove(id);
    }
  }

  int _resolveJoinOrder({required String playerId, required String username}) {
    if (playerId.isNotEmpty && _joinOrderByPlayerId.containsKey(playerId)) {
      return _joinOrderByPlayerId[playerId]!;
    }
    if (_joinOrderByUsername.containsKey(username)) {
      final existing = _joinOrderByUsername[username]!;
      if (playerId.isNotEmpty) _joinOrderByPlayerId[playerId] = existing;
      return existing;
    }
    final order = _nextJoinOrder;
    _nextJoinOrder += 1;
    if (playerId.isNotEmpty) _joinOrderByPlayerId[playerId] = order;
    _joinOrderByUsername[username] = order;
    return order;
  }

  void _appendChatMessage({
    required String playerId,
    required String senderName,
    required String content,
    required _FeedKind kind,
    String? key,
  }) {
    final order = _resolveJoinOrder(playerId: playerId, username: senderName);
    setState(() {
      _messages.add(
        _RoomFeedEntry(
          key: key,
          joinOrder: order,
          username: senderName,
          content: content,
          kind: kind,
        ),
      );
    });
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_feedScrollController.hasClients) return;
      _feedScrollController.animateTo(
        _feedScrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  List<PlayerModel> _seatModels() {
    final cap = _room.maxPlayers.clamp(1, 16);
    return List.generate(cap, (i) {
      if (i < _room.players.length) {
        final rp = _room.players[i];
        return PlayerModel(
          number: i + 1,
          name: rp.username,
          playerId: rp.playerId.isEmpty ? null : rp.playerId,
        );
      }
      return PlayerModel(number: i + 1, name: 'ว่าง');
    });
  }

  int _mySeatNumber() {
    final myId = (AuthService.currentUser.value?.userId ?? '').trim().toLowerCase();
    if (myId.isEmpty) return 1;
    for (var i = 0; i < _room.players.length; i++) {
      if (_room.players[i].playerId.trim().toLowerCase() == myId) return i + 1;
    }
    final myName =
        (AuthService.currentUser.value?.username ?? '').trim().toLowerCase();
    if (myName.isNotEmpty) {
      for (var i = 0; i < _room.players.length; i++) {
        if (_room.players[i].username.trim().toLowerCase() == myName) {
          return i + 1;
        }
      }
    }
    return 1;
  }

  void _sendLobbyChat() {
    final text = _chatController.text.trim();
    if (text.isEmpty) return;
    final myId = AuthService.currentUser.value?.userId ?? '';
    final me = AuthService.currentUser.value?.username ?? 'ผู้เล่น';
    _appendChatMessage(
      playerId: myId,
      senderName: me,
      content: text,
      kind: _FeedKind.message,
    );
    _chatController.clear();
  }

  void _openInvite() {
    final code = _room.inviteCode;
    if (code == null || code.isEmpty) return;
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => InviteFriendsDialog(inviteCode: code),
    );
  }

  void _goRandomRole({Map<String, dynamic>? startPayload}) {
    if (_navigated || !mounted) return;
    _navigated = true;
    _countdownTimer?.cancel();
    final myId = AuthService.currentUser.value?.userId ?? '';
    final payload = startPayload ?? const <String, dynamic>{};
    final rolesByPlayerIdRaw = payload['rolesByPlayerId'];
    final rolePoolRaw = payload['rolePool'];
    final initialPhase = payload['phase'] as String?;
    final initialDeadline = payload['phaseDeadlineAt'] as int?;
    final rolesByPlayerId = <String, String>{};
    if (rolesByPlayerIdRaw is Map) {
      rolesByPlayerIdRaw.forEach((key, value) {
        if (key is String && value is String && key.isNotEmpty && value.isNotEmpty) {
          rolesByPlayerId[key] = value;
        }
      });
    }
    final rolePool = <String>[
      if (rolePoolRaw is List)
        ...rolePoolRaw.whereType<String>().where((e) => e.trim().isNotEmpty),
    ];
    final myAssignedRole = myId.isNotEmpty ? rolesByPlayerId[myId] : null;
    Navigator.pushReplacement<void, void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => RandomRoleScreen(
          roomId: _room.roomId,
          playerCount: _room.players.length,
          forcedRole: myAssignedRole,
          serverRolePool: rolePool,
          serverRolesByPlayerId: rolesByPlayerId,
          initialPhase: initialPhase,
          initialPhaseDeadlineAt: initialDeadline,
          playerNamesInJoinOrder: _room.players.map((p) => p.username).toList(growable: false),
        ),
      ),
    );
  }

  void _handleLeave() {
    WsService.instance.leaveRoom();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final myId = AuthService.currentUser.value?.userId ?? '';
    final isHost = widget.isHost || _room.players.any((p) => p.playerId == myId && p.isHost);
    final canInvite = isHost && (_room.inviteCode?.isNotEmpty ?? false);

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/images/DayTimeBg.jpg',
              fit: BoxFit.cover,
              alignment: Alignment.center,
            ),
          ),
          Positioned.fill(
            child: Container(
              color: Colors.black.withValues(alpha: 0.35),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 6, 8, 4),
                  child: Row(
                    children: [
                      IconButton(
                        icon: Icon(PhosphorIcons.caretLeft(), color: Colors.white, size: 30),
                        onPressed: _handleLeave,
                      ),
                      Expanded(
                        child: Column(
                          children: [
                            const SizedBox(height: 33),
                            Text(
                              _quickplayCountdown == null
                                  ? 'รอผู้เล่น...'
                                  : _quickplayCountdown! > 0
                                      ? 'เริ่มเกมใน $_quickplayCountdown วินาที'
                                      : 'กำลังเริ่มเกม...',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                shadows: [
                                  Shadow(
                                    blurRadius: 8,
                                    color: Colors.black.withValues(alpha: 0.65),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (canInvite)
                        IconButton(
                          icon: Icon(PhosphorIcons.userPlus(), color: Colors.white, size: 28),
                          onPressed: _openInvite,
                        )
                      else
                        const SizedBox(width: 48),
                    ],
                  ),
                ),
                Expanded(
                  flex: 5,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: PlayerGridDay(
                      players: _seatModels(),
                      myPlayerNumber: _mySeatNumber(),
                      myAuthUserId: AuthService.currentUser.value?.userId,
                      dayVoteTargetByVoter: const <int, int>{},
                      dayVoteCountByTarget: const <int, int>{},
                      dayVoteEnabled: false,
                      onPlayerTap: (_) {},
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 220,
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 12),
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x1F000000),
                          blurRadius: 12,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ScrollConfiguration(
                      behavior: const MaterialScrollBehavior().copyWith(scrollbars: false),
                      child: ListView.builder(
                        controller: _feedScrollController,
                        itemCount: _messages.length,
                        itemBuilder: (_, i) {
                          final m = _messages[i];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: RichText(
                              text: TextSpan(
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontFamily: 'Charmonman',
                                ),
                                children: m.kind == _FeedKind.system
                                    ? [
                                        TextSpan(
                                          text: m.content,
                                          style: const TextStyle(
                                            fontFamily: 'Charmonman',
                                            color: Colors.white,
                                            fontWeight: FontWeight.w400,
                                          ),
                                        ),
                                      ]
                                    : [
                                        TextSpan(text: '${m.joinOrder} '),
                                        TextSpan(text: '${m.username} '),
                                        TextSpan(
                                          text: m.content,
                                          style: TextStyle(
                                            fontFamily: 'Charmonman',
                                            color: switch (m.kind) {
                                              _FeedKind.joined => const Color(0xFF4DD6C9),
                                              _FeedKind.left => const Color(0xFFFF6B6B),
                                              _FeedKind.message => Colors.white,
                                              _FeedKind.system => Colors.white,
                                            },
                                            fontWeight: m.kind == _FeedKind.message
                                                ? FontWeight.w400
                                                : FontWeight.w600,
                                          ),
                                        ),
                                      ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
                  child: Row(
                    children: [
                      IconButton(
                        icon: Icon(PhosphorIcons.maskHappy(), color: Colors.white, size: 26),
                        onPressed: () {
                          showDialog<void>(
                            context: context,
                            builder: (_) => const RolesDialog(),
                          );
                        },
                      ),
                      Expanded(
                        child: InviteChat(
                          controller: _chatController,
                          onSend: _sendLobbyChat,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum _FeedKind { joined, left, message, system }

class _RoomFeedEntry {
  final String? key;
  final int joinOrder;
  final String username;
  final String content;
  final _FeedKind kind;

  const _RoomFeedEntry({
    this.key,
    required this.joinOrder,
    required this.username,
    required this.content,
    required this.kind,
  });
}
