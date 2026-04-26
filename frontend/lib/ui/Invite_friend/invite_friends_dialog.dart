import 'package:areyoughost/services/auth_service.dart';
import 'package:areyoughost/services/friend_service.dart';
import 'package:areyoughost/services/ws_service.dart';
import 'package:flutter/material.dart';

class InviteFriendsDialog extends StatefulWidget {
  final String inviteCode;

  const InviteFriendsDialog({super.key, required this.inviteCode});

  @override
  State<InviteFriendsDialog> createState() => _InviteFriendsDialogState();
}

class _InviteFriendsDialogState extends State<InviteFriendsDialog> {
  final TextEditingController _searchController = TextEditingController();
  FriendsOverview _overview = const FriendsOverview(
    incomingRequests: <IncomingFriendRequest>[],
    friends: <FriendItem>[],
    outgoingRequests: <OutgoingFriendRequest>[],
  );
  bool _loading = false;
  String? _error;
  final Set<String> _pending = <String>{};

  @override
  void initState() {
    super.initState();
    _loadFriends();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadFriends() async {
    final userId = AuthService.currentUser.value?.userId;
    if (userId == null || userId.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final overview = await FriendService.getOverview(userId);
      if (!mounted) return;
      setState(() {
        _overview = overview;
        _pending
          ..clear()
          ..addAll(overview.outgoingRequests.map((e) => e.playerId));
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  Future<void> _invite(FriendItem friend) async {
    if (_pending.contains(friend.playerId)) return;
    try {
      final msg = await WsService.instance.sendInviteAndWait(friend.playerId, widget.inviteCode);
      if (!mounted) return;
      if (msg['type'] == 'invite.sent') {
        setState(() => _pending.add(friend.playerId));
      } else {
        final payload = msg['payload'];
        final code = payload is Map ? payload['code'] as String? : null;
        final message = payload is Map ? payload['message'] as String? : null;
        setState(() {
          if (code == 'FRIEND_NOT_ONLINE') {
            _error = 'เพื่อนไม่ออนไลน์ (ต้องเปิดเกมและเชื่อมต่อเซิร์ฟเวอร์อยู่)';
          } else {
            _error = message ?? 'ส่งคำเชิญไม่สำเร็จ';
          }
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'ส่งคำเชิญไม่สำเร็จ');
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _searchController.text.trim().toLowerCase();
    final friends = _overview.friends
        .where((f) => q.isEmpty || f.username.toLowerCase().contains(q))
        .toList(growable: false);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 86),
      backgroundColor: const Color(0xFFF3F3F3),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: SizedBox(
        width: 360,
        height: 560,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Align(
                alignment: Alignment.topRight,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.black, size: 40),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
              const Center(
                child: Text(
                  'เพื่อนทั้งหมด',
                  style: TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.bold,
                    decoration: TextDecoration.underline,
                    color: Colors.black,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Container(
                height: 50,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(26),
                  boxShadow: const [
                    BoxShadow(
                      color: Color.fromARGB(80, 0, 0, 0),
                      blurRadius: 10,
                      offset: Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        onChanged: (_) => setState(() {}),
                        style: const TextStyle(color: Colors.black, fontSize: 18),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          hintText: 'เพิ่มเพื่อนด้วยชื่อบัญชีผู้ใช้งาน',
                          hintStyle: TextStyle(color: Color(0xFFB8B8B8), fontSize: 16),
                        ),
                      ),
                    ),
                    const Icon(Icons.search, size: 40, color: Colors.black),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              if (_loading) const LinearProgressIndicator(minHeight: 2),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                  ),
                ),
              const SizedBox(height: 10),
              Expanded(
                child: ListView.separated(
                  itemCount: friends.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final f = friends[index];
                    final pending = _pending.contains(f.playerId);
                    return Row(
                      children: [
                        Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            color: f.isOnline ? const Color(0xFF018A0C) : Colors.red,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            f.username,
                            style: const TextStyle(
                              color: Colors.black,
                              fontSize: 19,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: (!pending && f.isOnline) ? () => _invite(f) : null,
                          child: Text(
                            pending ? 'รอการตอบรับ' : (f.isOnline ? 'ส่งคำเชิญ' : 'ออฟไลน์'),
                            style: TextStyle(
                              color: pending
                                  ? Colors.black87
                                  : (f.isOnline ? Colors.black : Colors.black45),
                              fontSize: 17,
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
