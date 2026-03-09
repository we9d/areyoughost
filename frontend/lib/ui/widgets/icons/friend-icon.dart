import 'package:areyoughost/ui/dialogs/friend_request_dialog.dart';
import 'package:areyoughost/ui/game/widgets/friend_search_bar.dart';
import 'package:flutter/material.dart';
import 'package:bootstrap_icons/bootstrap_icons.dart';
import 'package:areyoughost/ui/dialogs/friend_request_dialog.dart';

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

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _showFriendRequestPopup() {
    FriendRequestPopup.show(
      context: context,
      friendName: 'น้องดิว ทุกสถาบัน',
      onAccept: () {
        // logic ตอนกดยอมรับ
      },
      onReject: () {
        // logic ตอนกดปฏิเสธ
      },
    );
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
                    onSearchPressed: () {
                      FocusScope.of(context).unfocus();
                    },
                  ),
                  const SizedBox(height: 22),
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
                            const _FriendSectionTitle(
                              title: 'คำขอเป็นเพื่อน (1)',
                            ),
                            const SizedBox(height: 8),
                            _FriendRequestName(
                              name: 'น้องดิว ทุกสถาบัน',
                              onTap: _showFriendRequestPopup,
                            ),
                            const SizedBox(height: 26),
                            const _FriendSectionTitle(
                              title: 'รายชื่อเพื่อนทั้งหมด (2)',
                            ),
                            const SizedBox(height: 10),
                            const _FriendStatusItem(
                              name: 'น้องข้าว พาเพลิน',
                              statusColor: Color(0xFF0D9B18),
                            ),
                            const SizedBox(height: 14),
                            const _FriendStatusItem(
                              name: 'น้องบูม',
                              statusColor: Color(0xFFD80D0D),
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
  final VoidCallback onTap;

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