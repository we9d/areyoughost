import 'package:flutter/material.dart';
import 'package:areyoughost/models/mock_models.dart';
import 'package:areyoughost/models/room_model.dart';
import 'package:areyoughost/services/auth_service.dart';
import 'package:areyoughost/services/lobby_service.dart';
import 'package:areyoughost/services/session_manager.dart';
import 'package:areyoughost/services/ws_service.dart';
import 'package:areyoughost/ui/game/game_pre_lobby_screen.dart';
import 'package:areyoughost/ui/game/mode_select_screen.dart';

class LobbyScreen extends StatefulWidget {
  const LobbyScreen({super.key});

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  List<Room> _rooms = [];
  bool _loading = true;
  String? _error;
  bool _joining = false;

  @override
  void initState() {
    super.initState();
    _loadRooms();
  }

  Future<void> _loadRooms() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await LobbyService.fetchPublicRooms();
      if (!mounted) return;
      setState(() {
        _rooms = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
        _loading = false;
        _rooms = [];
      });
    }
  }

  Future<void> _ensureWsAuthenticated() async {
    if (WsService.instance.isConnected) return;
    final session = await SessionManager.getSession();
    final token = session?['token'];
    if (token == null || token.isEmpty) {
      throw StateError('กรุณาเข้าสู่ระบบก่อน');
    }
    await WsService.instance.connect(token);
    await WsService.instance.waitForAny(
      {'auth.ok', 'session.resumed'},
      timeout: const Duration(seconds: 8),
    );
  }

  Future<void> _joinRoom(Room room) async {
    if (_joining) return;
    final isFull = room.currentPlayers >= room.maxPlayers;
    final isPlaying = room.status == 'playing';
    if (isFull || isPlaying) return;

    setState(() => _joining = true);
    try {
      await _ensureWsAuthenticated();
      WsService.instance.joinRoom(room.roomId);
      final expireAt = DateTime.now().add(const Duration(seconds: 14));
      Map<String, dynamic>? payload;
      while (DateTime.now().isBefore(expireAt)) {
        final remaining = expireAt.difference(DateTime.now());
        final msg = await WsService.instance.waitForAny(
          {'room.state', 'error'},
          timeout: remaining.inMilliseconds > 0
              ? remaining
              : const Duration(milliseconds: 200),
        );
        final type = msg['type'] as String?;
        if (type == 'error') {
          final errPayload = msg['payload'];
          final detail =
              errPayload is Map ? errPayload['message'] as String? : null;
          throw Exception(
            detail?.isNotEmpty == true ? detail! : 'เข้าห้องไม่สำเร็จ',
          );
        }
        final p = msg['payload'] as Map<String, dynamic>?;
        final rid = p?['roomId'] as String?;
        if (rid == room.roomId) {
          payload = p;
          break;
        }
      }
      if (payload == null || !mounted) {
        throw Exception('หมดเวลารอเข้าห้อง');
      }
      final roomModel = RoomModel.fromJson(payload);
      final myId = AuthService.currentUser.value?.userId ?? '';
      final isHost = roomModel.players.any(
        (p) =>
            p.playerId.toLowerCase() == myId.toLowerCase() && p.isHost,
      );
      if (!mounted) return;
      setState(() => _joining = false);
      await Navigator.push<void>(
        context,
        MaterialPageRoute<void>(
          builder: (_) => GamePreLobbyScreen(
            initialRoom: roomModel,
            isHost: isHost,
            initialQuickplayDeadlineUnix:
                payload!['quickplayDeadlineUnix'] as int?,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _joining = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Lobby'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading || _joining ? null : _loadRooms,
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {},
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Column(
            children: [
              _buildQuickPlayBanner(context),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Text(
                    _error!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _rooms.isEmpty
                        ? Center(
                            child: Text(
                              'ยังไม่มีห้องเปิดตอนนี้\nกดรีเฟรชหรือสร้างห้องใหม่',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.grey[600]),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: _rooms.length,
                            itemBuilder: (context, index) {
                              final room = _rooms[index];
                              return _buildRoomCard(context, room);
                            },
                          ),
              ),
            ],
          ),
          if (_joining)
            Positioned.fill(
              child: Container(
                color: Colors.black26,
                alignment: Alignment.center,
                child: const CircularProgressIndicator(),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _joining
            ? null
            : () {
                Navigator.push<void>(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => const ModeSelectScreen(),
                  ),
                );
              },
        label: const Text('สร้าง / เล่นกับเพื่อน'),
        icon: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildQuickPlayBanner(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
          ),
        ),
      ),
      child: Column(
        children: [
          const Text(
            'Ready to hunt?',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: _joining
                ? null
                : () {
                    Navigator.push<void>(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => const ModeSelectScreen(),
                      ),
                    );
                  },
            child: const Text('เล่นทันที / เลือกโหมด'),
          ),
        ],
      ),
    );
  }

  Widget _buildRoomCard(BuildContext context, Room room) {
    final isFull = room.currentPlayers >= room.maxPlayers;
    final isPlaying = room.status == 'playing';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: _joining || isFull || isPlaying ? null : () => _joinRoom(room),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: isPlaying
                      ? Colors.red.withValues(alpha: 0.2)
                      : Colors.green.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isPlaying ? Icons.sports_esports : Icons.meeting_room,
                  color: isPlaying ? Colors.red : Colors.green,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      room.roomName,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (!room.isPublic)
                          const Padding(
                            padding: EdgeInsets.only(right: 8),
                            child: Icon(Icons.lock, size: 14, color: Colors.grey),
                          ),
                        Text(
                          '${room.currentPlayers}/${room.maxPlayers} ผู้เล่น',
                          style: TextStyle(color: Colors.grey[400], fontSize: 12),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (isPlaying)
                Chip(
                  label: const Text('กำลังเล่น'),
                  backgroundColor: Colors.red.withValues(alpha: 0.2),
                  labelStyle: const TextStyle(fontSize: 10),
                )
              else if (isFull)
                const Chip(label: Text('เต็ม'))
              else
                const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}
