import 'dart:async';

import 'package:areyoughost/models/room_model.dart';
import 'package:areyoughost/services/invite_store.dart';
import 'package:areyoughost/services/ws_service.dart';
import 'package:areyoughost/ui/lobby/waiting_room_screen.dart';
import 'package:areyoughost/ui/widgets/buttons/accept_invite_button.dart';
import 'package:areyoughost/ui/widgets/buttons/reject_invite_button.dart';
import 'package:bootstrap_icons/bootstrap_icons.dart';
import 'package:flutter/material.dart';

/// Mail / notification icon that shows a badge when there are pending invites.
/// Tapping it shows the first pending invite dialog from InviteStore.
class MailNotiIcon extends StatefulWidget {
  const MailNotiIcon({super.key});

  @override
  State<MailNotiIcon> createState() => _MailNotiIconState();
}

class _MailNotiIconState extends State<MailNotiIcon> {
  bool _isAccepting = false;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<PendingInvite>>(
      valueListenable: InviteStore.instance.invites,
      builder: (context, invites, _) {
        final hasInvite = invites.isNotEmpty;
        return IconButton(
          onPressed: hasInvite ? () => _showInviteDialog(context, invites.first) : null,
          icon: Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(
                BootstrapIcons.envelope_open_fill,
                color: hasInvite ? Colors.white : Colors.white54,
                size: 23,
              ),
              if (hasInvite)
                Positioned(
                  top: -2,
                  right: -4,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  void _showInviteDialog(BuildContext context, PendingInvite invite) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _InviteDialog(
        invite: invite,
        isAccepting: _isAccepting,
        onAccept: () => _handleAccept(ctx, invite),
        onReject: () {
          InviteStore.instance.remove(invite.inviteCode);
          Navigator.pop(ctx);
        },
      ),
    );
  }

  Future<void> _handleAccept(BuildContext dialogCtx, PendingInvite invite) async {
    setState(() => _isAccepting = true);

    // Send accept + wait for room.joined from server
    WsService.instance.acceptInvite(invite.inviteCode);
    InviteStore.instance.remove(invite.inviteCode);

    try {
      final msg = await WsService.instance.waitFor(
        'room.joined',
        timeout: const Duration(seconds: 10),
      );
      final roomData = (msg['payload']?['room'] as Map<String, dynamic>?) ??
          (msg['payload'] as Map<String, dynamic>? ?? {});
      final room = RoomModel.fromJson(roomData);

      if (!mounted) return;
      Navigator.pop(dialogCtx); // Close dialog
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => WaitingRoomScreen(initialRoom: room, isHost: false),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      Navigator.pop(dialogCtx);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ไม่สามารถเข้าร่วมห้องได้ ลองใหม่อีกครั้ง')),
      );
    } finally {
      if (mounted) setState(() => _isAccepting = false);
    }
  }
}

class _InviteDialog extends StatelessWidget {
  final PendingInvite invite;
  final bool isAccepting;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  const _InviteDialog({
    required this.invite,
    required this.isAccepting,
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
                    invite.fromUsername,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.black87,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'ชวนคุณเข้าร่วมเกม',
                    style: TextStyle(color: Colors.black54, fontSize: 14),
                  ),
                  const SizedBox(height: 26),
                  if (isAccepting)
                    const CircularProgressIndicator()
                  else
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
            if (!isAccepting)
              Positioned(
                top: -6,
                right: -8,
                child: IconButton(
                  splashRadius: 20,
                  icon: const Icon(Icons.close, size: 30, color: Colors.black),
                  onPressed: onReject,
                ),
              ),
          ],
        ),
      ),
    );
  }
}