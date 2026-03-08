import 'package:areyoughost/ui/widgets/buttons/accept_invite_button.dart';
import 'package:areyoughost/ui/widgets/buttons/reject_invite_button.dart';
import 'package:bootstrap_icons/bootstrap_icons.dart';
import 'package:flutter/material.dart';

class MailNotiIcon extends StatelessWidget {
  final bool hasInvite;
  final String inviterName;
  final VoidCallback? onAccept;
  final VoidCallback? onReject;

  const MailNotiIcon({
    super.key,
    this.hasInvite = true,
    this.inviterName = 'น้องดิว ทุกสถาบัน',
    this.onAccept,
    this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: () {
        if (!hasInvite) return;

        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) {
            return _InviteDialog(
              inviterName: inviterName,
              onAccept: () {
                Navigator.pop(context);
                onAccept?.call();
              },
              onReject: () {
                Navigator.pop(context);
                onReject?.call();
              },
            );
          },
        );
      },
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          const Icon(
            BootstrapIcons.envelope_open_fill,
            color: Colors.white,
            size: 23,
          ),
          if (hasInvite)
            Positioned(
              top: -1,
              right: 15,
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _InviteDialog extends StatelessWidget {
  final String inviterName;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  const _InviteDialog({
    required this.inviterName,
    required this.onAccept,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 22),
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Container(
        width: 358,
        padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
        decoration: BoxDecoration(
          color: const Color(0xFFF4F4F4),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 6),
                  const Text(
                    'ตอบรับคำเชิญเข้าเกม',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 19,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    inviterName,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.black87,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 26),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      RejectInviteButton(onPressed: onReject),
                      const SizedBox(width: 18),
                      AcceptInviteButton(onPressed: onAccept),
                    ],
                  ),
                ],
              ),
            ),
            Positioned(
              top: -6,
              right: -8,
              child: IconButton(
                splashRadius: 20,
                icon: const Icon(
                  Icons.close,
                  size: 30,
                  color: Colors.black,
                ),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}