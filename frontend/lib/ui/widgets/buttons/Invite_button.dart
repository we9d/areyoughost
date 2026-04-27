import 'package:flutter/material.dart';
import 'package:areyoughost/ui/widgets/buttons/decoration/shadow.dart';
import 'package:areyoughost/ui/widgets/search_friend.dart';
import 'package:areyoughost/ui/widgets/friend_status.dart';

class InviteButton extends StatelessWidget {
  final VoidCallback? onPressed;

  const InviteButton({super.key, this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      child: Shadow(
        height: 40,
        width: 315,
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF555555),
            Color(0xFFD9D9D9),
          ],
          stops: [0.0, 1.25],
        ),
        onPressed: onPressed ?? () => _showInvitePopup(context),
        child: const Padding(
          padding: EdgeInsets.only(top: 10),
          child: Text(
            "เชิญเพื่อน",
            style: TextStyle(
              color: Colors.black,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
}

void _showInvitePopup(BuildContext context) {
  showDialog(
    context: context,
    builder: (_) => const _InviteDialog(),
  );
}

class _InviteDialog extends StatelessWidget {
  const _InviteDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: EdgeInsets.symmetric(horizontal: 15, vertical: 90),
      backgroundColor: Colors.white,
      child: SizedBox(
        width: 350,
        height: 550,
        child: Stack(
          children: [

            /// ปุ่มปิด
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.black),
                onPressed: () {
                  Navigator.pop(context);
                },
              ),
            ),

            /// Title
            const Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: EdgeInsets.only(top: 16),
                child: Text(
                  "เพื่อนทั้งหมด",
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    decoration: TextDecoration.underline,
                    decorationColor: Colors.black,
                    color: Colors.black,
                  ),
                ),
              ),
            ),

            /// Search Friend 
            const Positioned(
              top: 70,
              left: 20,
              right: 20,
              child: SearchFriend(),
            ),

            /// Friend Status
            const Positioned(
              top: 135,
              left: 20,
              right: 20,
              child: FriendStatusList(),
            ),

          ],
        ),
      ),
    );
  }
}