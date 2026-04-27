import 'dart:async';

import 'package:areyoughost/models/room_model.dart';
import 'package:areyoughost/services/ws_service.dart';
import 'package:areyoughost/ui/Invite_friend/invite_friends_dialog.dart';
import 'package:areyoughost/ui/game/game_started_roles.dart';
import 'package:areyoughost/ui/game/random_role_screen.dart';
import 'package:areyoughost/ui/widgets/buttons/Invite_chat.dart';
import 'package:areyoughost/ui/widgets/buttons/Invite_button.dart';
import 'package:areyoughost/ui/widgets/buttons/start_game_buttons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

class HostRoomScreen extends StatefulWidget {
  final RoomModel initialRoom;
  final bool showHostControls;

  const HostRoomScreen({
    super.key,
    required this.initialRoom,
    this.showHostControls = true,
  });

  @override
  State<HostRoomScreen> createState() => _HostRoomScreenState();
}

class _HostRoomScreenState extends State<HostRoomScreen> {
  final TextEditingController messageController = TextEditingController();
  final List<_RoomFeedEntry> _messages = <_RoomFeedEntry>[];
  final ScrollController _feedScrollController = ScrollController();
  StreamSubscription<Map<String, dynamic>>? _sub;
  VoidCallback? _wsConnectionListener;
  late RoomModel _room;
  final Set<String> _knownPlayerIds = <String>{};
  final Map<String, int> _joinOrderByPlayerId = <String, int>{};
  final Map<String, int> _joinOrderByUsername = <String, int>{};
  int _nextJoinOrder = 1;
  int _debugBotSeq = 1;
  bool _startingGame = false;
  bool _navigatedToGame = false;

  @override
  void initState() {
    super.initState();
    _room = widget.initialRoom;
    _seedInitialJoinFeed();
    _sub = WsService.instance.stream.listen(_onServerMessage);
    _wsConnectionListener = () {
      if (!mounted) return;
      if (WsService.instance.connectionStatus.value ==
          WsConnectionStatus.connected) {
        WsService.instance.syncRoom();
      }
    };
    WsService.instance.connectionStatus.addListener(_wsConnectionListener!);
  }

  @override
  void dispose() {
    if (_wsConnectionListener != null) {
      WsService.instance.connectionStatus
          .removeListener(_wsConnectionListener!);
    }
    _sub?.cancel();
    _feedScrollController.dispose();
    messageController.dispose();
    super.dispose();
  }

  void _onServerMessage(Map<String, dynamic> msg) {
    final type = msg['type'] as String?;
    if (type == null) return;

    switch (type) {
      case 'room.state':
        final payload = msg['payload'] as Map<String, dynamic>?;
        if (!mounted || payload == null) return;
        final nextRoom = RoomModel.fromJson(payload);
        _syncMembershipFeedFromState(nextRoom);
        setState(() => _room = nextRoom);
        break;
      case 'game.started':
        final startedPayload =
            msg['payload'] as Map<String, dynamic>? ?? <String, dynamic>{};
        _navigateToRandomRole(startPayload: startedPayload);
        break;
      case 'room.player_joined':
        final p = msg['payload'] as Map<String, dynamic>? ?? <String, dynamic>{};
        final playerId = (p['playerId'] as String?) ?? '';
        final username = (p['username'] as String?) ?? 'เพื่อน';
        if (!mounted) return;
        _appendFeed(
          playerId: playerId,
          username: username,
          content: 'เข้าร่วม',
          kind: _FeedKind.joined,
        );
        break;
      case 'room.player_left':
        final p = msg['payload'] as Map<String, dynamic>? ?? <String, dynamic>{};
        final playerId = (p['playerId'] as String?) ?? '';
        final username = (p['username'] as String?) ?? 'เพื่อน';
        if (!mounted) return;
        _appendFeed(
          playerId: playerId,
          username: username,
          content: 'ออกจากห้อง',
          kind: _FeedKind.left,
        );
        break;
      case 'room.chat_message':
        final p = msg['payload'] as Map<String, dynamic>? ?? <String, dynamic>{};
        final text = (p['text'] as String?)?.trim() ?? '';
        if (text.isEmpty) return;
        _appendFeed(
          playerId: (p['playerId'] as String?) ?? '',
          username: (p['username'] as String?) ?? 'ผู้เล่น',
          content: text,
          kind: _FeedKind.message,
        );
        break;
      case 'error':
        final payload = msg['payload'] as Map<String, dynamic>? ?? <String, dynamic>{};
        final code = payload['code'] as String?;
        if (code == 'GAME_START_FAILED' || code == 'INVALID_PAYLOAD') {
          if (mounted) {
            if (_startingGame) setState(() => _startingGame = false);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  (payload['message'] as String?) ??
                      (code == 'GAME_START_FAILED' ? 'เริ่มเกมไม่สำเร็จ' : 'ส่งข้อความไม่สำเร็จ'),
                ),
              ),
            );
          }
        }
        break;
    }
  }

  void _navigateToRandomRole({Map<String, dynamic>? startPayload}) {
    if (!mounted || _navigatedToGame) return;
    _navigatedToGame = true;
    if (_startingGame) {
      setState(() => _startingGame = false);
    }
    final payload = startPayload ?? const <String, dynamic>{};
    final rolesByPlayerId = parseRolesByPlayerIdFromPayload(payload['rolesByPlayerId']);
    final rolePool = parseRolePoolFromPayload(payload['rolePool']);
    final myAssignedRole = assignedRoleForCurrentUser(rolesByPlayerId);
    final initialPhase = payload['phase'] as String?;
    final initialDeadline = payload['phaseDeadlineAt'] as int?;
    Navigator.push<void>(
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
          playerNamesInJoinOrder: _room.players
              .map((p) => p.username)
              .toList(growable: false),
        ),
      ),
    );
  }

  void _requestStartGame() {
    if (_startingGame) return;
    if (_room.players.length < 2) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ต้องมีผู้เล่นอย่างน้อย 2 คนก่อนเริ่มเกม')),
        );
      }
      return;
    }
    setState(() => _startingGame = true);
    WsService.instance.send('game.start', {});
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

  void _appendFeed({
    required String playerId,
    required String username,
    required String content,
    required _FeedKind kind,
    bool notify = true,
  }) {
    final order = _resolveJoinOrder(playerId: playerId, username: username);
    void append() {
      _messages.add(
        _RoomFeedEntry(
          joinOrder: order,
          username: username,
          content: content,
          kind: kind,
        ),
      );
    }
    if (notify) {
      setState(append);
      _scrollToBottom();
    } else {
      append();
    }
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

  void _seedInitialJoinFeed() {
    for (final player in _room.players) {
      _knownPlayerIds.add(player.playerId);
      _appendFeed(
        playerId: player.playerId,
        username: player.username,
        content: 'เข้าร่วม',
        kind: _FeedKind.joined,
        notify: false,
      );
    }
  }

  void _syncMembershipFeedFromState(RoomModel nextRoom) {
    final nextById = <String, PlayerInfo>{
      for (final p in nextRoom.players) p.playerId: p,
    };

    // joined
    for (final entry in nextById.entries) {
      if (!_knownPlayerIds.contains(entry.key)) {
        _knownPlayerIds.add(entry.key);
        _appendFeed(
          playerId: entry.key,
          username: entry.value.username,
          content: 'เข้าร่วม',
          kind: _FeedKind.joined,
        );
      }
    }

    // left
    final removed = _knownPlayerIds.where((id) => !nextById.containsKey(id)).toList();
    if (removed.isNotEmpty) {
      final prevById = <String, PlayerInfo>{
        for (final p in _room.players) p.playerId: p,
      };
      for (final id in removed) {
        final username = prevById[id]?.username ?? 'ผู้เล่น';
        _appendFeed(
          playerId: id,
          username: username,
          content: 'ออกจากห้อง',
          kind: _FeedKind.left,
        );
        _knownPlayerIds.remove(id);
      }
    }
  }

  void _sendMessage() {
    final text = messageController.text.trim();
    if (text.isEmpty) return;
    WsService.instance.send('room.chat', {'text': text});
    messageController.clear();
  }

  void _openInvitePanel() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => InviteFriendsDialog(inviteCode: _room.inviteCode ?? ''),
    );
  }

  void _simulateJoinForDebug() {
    if (!kDebugMode) return;
    if (_room.players.length >= _room.maxPlayers) return;

    String playerId = 'debug-bot-${_debugBotSeq.toString().padLeft(2, '0')}';
    while (_room.players.any((p) => p.playerId == playerId)) {
      _debugBotSeq += 1;
      playerId = 'debug-bot-${_debugBotSeq.toString().padLeft(2, '0')}';
    }
    final username = 'ผู้เล่นทดสอบ$_debugBotSeq';
    _debugBotSeq += 1;

    final nextPlayers = <PlayerInfo>[
      ..._room.players,
      PlayerInfo(
        playerId: playerId,
        username: username,
        isHost: false,
        isReady: false,
      ),
    ];
    setState(() => _room = _room.copyWith(players: nextPlayers));
    _knownPlayerIds.add(playerId);
    _appendFeed(
      playerId: playerId,
      username: username,
      content: 'เข้าร่วม',
      kind: _FeedKind.joined,
    );
  }

  void _simulateLeaveForDebug() {
    if (!kDebugMode) return;
    final idx = _room.players.lastIndexWhere((p) => p.playerId.startsWith('debug-bot-'));
    if (idx < 0) return;

    final leaving = _room.players[idx];
    final nextPlayers = <PlayerInfo>[..._room.players]..removeAt(idx);
    setState(() => _room = _room.copyWith(players: nextPlayers));
    _knownPlayerIds.remove(leaving.playerId);
    _appendFeed(
      playerId: leaving.playerId,
      username: leaving.username,
      content: 'ออกจากห้อง',
      kind: _FeedKind.left,
    );
  }

  @override
  Widget build(BuildContext context) {
    const double designWidth = 390;
    const double designHeight = 844;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: SizedBox(
          width: designWidth,
          height: designHeight,
          child: Stack(
            children: [
              Image.asset(
                'assets/images/InvitePage.jpg',
                fit: BoxFit.cover,
                width: designWidth,
                height: designHeight,
              ),
              Positioned(
                top: 60,
                left: 0,
                right: 0,
                child: Text(
                  'ยินดีต้อนรับเข้าสู่เกมใหม่ Ghostปะคะ?',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFFF1C232),
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (widget.showHostControls)
                Positioned(
                  top: 82,
                  left: 30,
                  right: 20,
                  child: Text(
                    'รหัสชวน ${_room.inviteCode ?? '-'}',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              Positioned(
                top: 110,
                left: 30,
                right: 20,
                bottom: 230,
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
                            children: [
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
              Positioned(
                top: 40,
                left: 8,
                child: IconButton(
                  icon: Icon(
                    PhosphorIcons.caretLeft(),
                    color: Colors.white,
                    size: 32,
                  ),
                  onPressed: () {
                    WsService.instance.leaveRoom();
                    Navigator.pop(context);
                  },
                ),
              ),
              if (kDebugMode)
                Positioned(
                  top: 38,
                  right: 8,
                  child: Row(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.28),
                          shape: BoxShape.circle,
                        ),
                        child: IconButton(
                          tooltip: 'จำลองผู้เล่นเข้าร่วม',
                          icon: const Icon(Icons.person_add_alt_1, color: Colors.white, size: 20),
                          onPressed: _simulateJoinForDebug,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.28),
                          shape: BoxShape.circle,
                        ),
                        child: IconButton(
                          tooltip: 'จำลองผู้เล่นออกจากห้อง',
                          icon: const Icon(Icons.person_remove_alt_1, color: Colors.white, size: 20),
                          onPressed: _simulateLeaveForDebug,
                        ),
                      ),
                    ],
                  ),
                ),
              if (widget.showHostControls)
                Positioned(
                  top: 615,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: StartGameButton(
                      onPressed: _requestStartGame,
                    ),
                  ),
                ),
              Positioned(
                top: 668,
                left: 0,
                right: 0,
                child: Center(
                  child: InviteButton(onPressed: _openInvitePanel),
                ),
              ),
              Positioned(
                bottom: 20,
                left: 20,
                right: 20,
                child: InviteChat(
                  controller: messageController,
                  onSend: _sendMessage,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _FeedKind { joined, left, message }

class _RoomFeedEntry {
  final int joinOrder;
  final String username;
  final String content;
  final _FeedKind kind;

  const _RoomFeedEntry({
    required this.joinOrder,
    required this.username,
    required this.content,
    required this.kind,
  });
}