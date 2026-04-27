import 'dart:async';

import 'package:areyoughost/services/auth_service.dart';
import 'package:areyoughost/services/friend_service.dart';
import 'package:areyoughost/services/player_service.dart';
import 'package:areyoughost/services/ws_service.dart';
import 'package:areyoughost/ui/dialogs/friend_request_dialog.dart';
import 'package:areyoughost/ui/game/widgets/friend_search_bar.dart';
import 'package:flutter/material.dart';
import 'package:bootstrap_icons/bootstrap_icons.dart';

class AddFriendIcon extends StatelessWidget {
  const AddFriendIcon({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
      icon: const Icon(
        BootstrapIcons.person_plus_fill,
        color: Colors.white,
        size: 25,
      ),
      onPressed: () {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => const _AddFriendDialog(),
        );
      },
    );
  }
}

class _AddFriendDialog extends StatefulWidget {
  const _AddFriendDialog();

  @override
  State<_AddFriendDialog> createState() => _AddFriendDialogState();
}

class _AddFriendDialogState extends State<_AddFriendDialog> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final Set<String> _pendingSentPlayerIds = <String>{};
  Timer? _debounce;
  bool _searching = false;
  bool _loadingOverview = false;
  bool _sending = false;
  String? _error;
  List<PlayerLookupItem> _results = const <PlayerLookupItem>[];
  FriendsOverview _overview = const FriendsOverview(
    incomingRequests: <IncomingFriendRequest>[],
    friends: <FriendItem>[],
    outgoingRequests: <OutgoingFriendRequest>[],
  );
  String _lastQuery = '';
  StreamSubscription<Map<String, dynamic>>? _wsSub;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _refreshOverview();
    _wsSub = WsService.instance.stream.listen(_onWsMessage);
  }

  @override
  void dispose() {
    _wsSub?.cancel();
    _debounce?.cancel();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onWsMessage(Map<String, dynamic> msg) {
    final type = msg['type'] as String?;
    if (type == null) return;
    if (type == 'friend.request.received' || type == 'friend.request.responded') {
      _refreshOverview();
    }
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _runSearch);
  }

  Future<void> _runSearch() async {
    final q = _searchController.text.trim();
    _lastQuery = q;
    if (q.length < 2) {
      if (!mounted) return;
      setState(() {
        _results = const <PlayerLookupItem>[];
        _error = null;
        _searching = false;
      });
      return;
    }

    final currentUserId = AuthService.currentUser.value?.userId;
    setState(() {
      _searching = true;
      _error = null;
    });

    try {
      final players = await PlayerService.searchPlayers(
        query: q,
        excludeUserId: currentUserId,
      );
      if (!mounted || _lastQuery != q) return;
      setState(() {
        _results = players;
        _searching = false;
      });
    } catch (e) {
      if (!mounted || _lastQuery != q) return;
      setState(() {
        _searching = false;
        _error = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  Future<void> _refreshOverview() async {
    final userId = AuthService.currentUser.value?.userId;
    if (userId == null || userId.isEmpty) return;

    setState(() {
      _loadingOverview = true;
    });
    try {
      final overview = await FriendService.getOverview(userId);
      if (!mounted) return;
      setState(() {
        _overview = overview;
        _pendingSentPlayerIds
          ..clear()
          ..addAll(overview.outgoingRequests.map((e) => e.playerId));
        _loadingOverview = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingOverview = false;
        _error = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  bool _isAlreadyFriend(String playerId) {
    return _overview.friends.any((f) => f.playerId == playerId);
  }

  void _openRequestDialog(IncomingFriendRequest req) {
    FriendRequestPopup.show(
      context: context,
      friendName: req.username,
      onAccept: () => _respondRequest(req, true),
      onReject: () => _respondRequest(req, false),
    );
  }

  Future<void> _respondRequest(IncomingFriendRequest req, bool accept) async {
    final userId = AuthService.currentUser.value?.userId;
    if (userId == null || userId.isEmpty) return;
    try {
      await FriendService.respondRequest(
        friendshipId: req.friendshipId,
        userId: userId,
        accept: accept,
      );
      await _refreshOverview();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceAll('Exception: ', ''));
    }
  }

  Future<void> _sendRequest(PlayerLookupItem target) async {
    final userId = AuthService.currentUser.value?.userId;
    if (userId == null || userId.isEmpty) return;
    if (_pendingSentPlayerIds.contains(target.playerId) || _isAlreadyFriend(target.playerId)) {
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await FriendService.sendRequest(fromUserId: userId, toUserId: target.playerId);
      if (!mounted) return;
      setState(() {
        _pendingSentPlayerIds.add(target.playerId);
        _sending = false;
      });
      await _refreshOverview();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Container(
        width: 360,
        height: 580,
        decoration: BoxDecoration(
          color: const Color(0xFFF3F3F3),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Stack(
          children: [
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                icon: const Icon(
                  Icons.close,
                  size: 34,
                  color: Colors.black,
                ),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Center(
                    child: Text(
                      'เพื่อน',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        decoration: TextDecoration.underline,
                        decorationThickness: 1.5,
                        decorationColor: Colors.black,
                        color: Colors.black,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  FriendSearchBar(
                    controller: _searchController,
                    hintText: 'เพิ่มเพื่อนด้วยชื่อบัญชีผู้ใช้งาน',
                    onSearchPressed: _runSearch,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'พิมพ์อย่างน้อย 2 ตัวอักษร เพื่อค้นหาผู้เล่นจากฐานข้อมูล',
                    style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                  ),
                  const SizedBox(height: 12),
                  if (_loadingOverview)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 10),
                      child: LinearProgressIndicator(minHeight: 2),
                    ),
                  if (_searching)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 10),
                      child: LinearProgressIndicator(minHeight: 2),
                    ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(
                        _error!,
                        style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                      ),
                    ),
                  if (_results.isNotEmpty)
                    Expanded(
                      child: RawScrollbar(
                        controller: _scrollController,
                        thumbVisibility: true,
                        trackVisibility: true,
                        thickness: 4,
                        radius: const Radius.circular(12),
                        thumbColor: const Color(0xFF4A4A4A),
                        trackColor: const Color(0xFFD1D1D1),
                        trackBorderColor: Colors.transparent,
                        child: ListView.separated(
                          controller: _scrollController,
                          padding: const EdgeInsets.only(right: 8),
                          itemCount: _results.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final p = _results[index];
                            final isFriend = _isAlreadyFriend(p.playerId);
                            final isPending = _pendingSentPlayerIds.contains(p.playerId);
                            return _SearchResultItem(
                              name: p.username,
                              onActionTap: isFriend || isPending || _sending
                                  ? null
                                  : () => _sendRequest(p),
                              actionLabel: isFriend
                                  ? 'เป็นเพื่อนแล้ว'
                                  : (isPending ? 'รอการตอบรับ' : 'เพิ่มเพื่อน'),
                            );
                          },
                        ),
                      ),
                    )
                  else
                    Expanded(
                      child: RawScrollbar(
                        controller: _scrollController,
                        thumbVisibility: true,
                        trackVisibility: true,
                        thickness: 4,
                        radius: const Radius.circular(12),
                        thumbColor: const Color(0xFF4A4A4A),
                        trackColor: const Color(0xFFD1D1D1),
                        trackBorderColor: Colors.transparent,
                        child: SingleChildScrollView(
                          controller: _scrollController,
                          padding: const EdgeInsets.only(right: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _FriendSectionTitle(
                                title: 'คำขอเป็นเพื่อน (${_overview.incomingRequests.length})',
                              ),
                              const SizedBox(height: 10),
                              if (_overview.incomingRequests.isEmpty)
                                const _FriendRequestName(
                                  name: 'ไม่มีคำขอเป็นเพื่อน',
                                  onTap: null,
                                )
                              else
                                ..._overview.incomingRequests.map(
                                  (r) => Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: _FriendRequestName(
                                      name: r.username,
                                      onTap: () => _openRequestDialog(r),
                                    ),
                                  ),
                                ),
                              const SizedBox(height: 22),
                              _FriendSectionTitle(
                                title: 'รายชื่อเพื่อนทั้งหมด (${_overview.friends.length})',
                              ),
                              const SizedBox(height: 10),
                              if (_overview.friends.isEmpty)
                                const _FriendRequestName(
                                  name: 'ยังไม่มีเพื่อน',
                                  onTap: null,
                                )
                              else
                                ..._overview.friends.map(
                                  (f) => Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: _FriendStatusItem(
                                      name: f.username,
                                      statusColor: f.isOnline
                                          ? const Color(0xFF0D9B18)
                                          : const Color(0xFFD80D0D),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FriendSectionTitle extends StatelessWidget {
  final String title;

  const _FriendSectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.bold,
        color: Colors.black,
      ),
    );
  }
}

class _FriendRequestName extends StatelessWidget {
  final String name;
  final VoidCallback? onTap;

  const _FriendRequestName({
    required this.name,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: InkWell(
        onTap: onTap,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        hoverColor: Colors.transparent,
        child: Text(
          name,
          style: const TextStyle(
            fontSize: 18,
            color: Colors.black87,
            height: 1.3,
          ),
        ),
      ),
    );
  }
}

class _SearchResultItem extends StatelessWidget {
  final String name;
  final String actionLabel;
  final VoidCallback? onActionTap;

  const _SearchResultItem({
    required this.name,
    required this.actionLabel,
    required this.onActionTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            name,
            style: const TextStyle(
              fontSize: 18,
              color: Colors.black87,
              height: 1.3,
            ),
          ),
        ),
        GestureDetector(
          onTap: onActionTap,
          child: Text(
            actionLabel,
            style: TextStyle(
              fontSize: 16,
              color: onActionTap == null ? Colors.black54 : Colors.black87,
            ),
          ),
        ),
      ],
    );
  }
}

class _FriendStatusItem extends StatelessWidget {
  final String name;
  final Color statusColor;

  const _FriendStatusItem({
    required this.name,
    required this.statusColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            name,
            style: const TextStyle(
              fontSize: 18,
              color: Colors.black87,
              height: 1.3,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: statusColor,
            shape: BoxShape.circle,
          ),
        ),
      ],
    );
  }
}