import 'package:flutter/material.dart';
import 'package:areyoughost/ui/widgets/buttons/accept_invite_button.dart';
import 'package:areyoughost/ui/widgets/buttons/reject_invite_button.dart';

class FriendRequestPopup extends StatelessWidget {
  final String friendName;
  final VoidCallback? onAccept;
  final VoidCallback? onReject;

  const FriendRequestPopup({
    super.key,
    required this.friendName,
    this.onAccept,
    this.onReject,
  });

  static void show({
    required BuildContext context,
    required String friendName,
    VoidCallback? onAccept,
    VoidCallback? onReject,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => FriendRequestPopup(
        friendName: friendName,
        onAccept: onAccept,
        onReject: onReject,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Container(
        width: 330,
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 24),
        decoration: BoxDecoration(
          color: const Color(0xFFF4F4F4),
          borderRadius: BorderRadius.circular(24),
          boxShadow: const [
            BoxShadow(
              color: Color.fromARGB(70, 0, 0, 0),
              blurRadius: 12,
              offset: Offset(0, 5),
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned(
              top: -6,
              right: -8,
              child: IconButton(
                icon: const Icon(
                  Icons.close,
                  size: 30,
                  color: Colors.black,
                ),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'ตอบรับคำขอเป็นเพื่อน',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    friendName,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.black87,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 26),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      RejectInviteButton(
                        onPressed: () {
                          Navigator.pop(context);
                          onReject?.call();
                        },
                      ),
                      const SizedBox(width: 18),
                      AcceptInviteButton(
                        onPressed: () {
                          Navigator.pop(context);
                          onAccept?.call();
                        },
                      ),
                    ],
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