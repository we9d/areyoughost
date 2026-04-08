import 'package:areyoughost/ui/Invite_friend/Invite_friend.dart';
import 'package:areyoughost/ui/widgets/buttons/accept_invite_button.dart';
import 'package:areyoughost/ui/widgets/buttons/reject_invite_button.dart';
import 'package:areyoughost/models/invite_model.dart';
import 'package:areyoughost/services/network_service.dart';
import 'package:bootstrap_icons/bootstrap_icons.dart';
import 'package:flutter/material.dart';

class MailNotiIcon extends StatelessWidget {
  const MailNotiIcon({super.key});

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink(); // Legacy WS invites removed
  }
}

class _InviteListDialog extends StatelessWidget {
  final List<Invite> invites;

  const _InviteListDialog({required this.invites});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 22),
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Container(
        width: 358,
        constraints: const BoxConstraints(maxHeight: 450),
        padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
        decoration: BoxDecoration(
          color: const Color(0xFFF4F4F4),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Stack(
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 6),
                const Text(
                  'คำเชิญเข้าเกม',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 19,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: invites.length,
                    separatorBuilder: (context, index) => const Divider(),
                    itemBuilder: (context, index) {
                      final invite = invites[index];
                      return _InviteItem(
                        invite: invite,
                        onAccept: () {
                          NetworkService().acceptInvite(invite.inviteCode);
                          if (invites.length <= 1) Navigator.pop(context); // Close if last one
                        },
                        onReject: () {
                          NetworkService().declineInvite(invite.inviteCode);
                          if (invites.length <= 1) Navigator.pop(context);
                        },
                      );
                    },
                  ),
                ),
              ],
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

class _InviteItem extends StatelessWidget {
  final Invite invite;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  const _InviteItem({
    required this.invite,
    required this.onAccept,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            invite.inviterName,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.black87,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
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
    );
  }
}