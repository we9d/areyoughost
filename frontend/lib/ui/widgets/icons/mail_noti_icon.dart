import 'dart:async';

import 'package:areyoughost/models/room_model.dart';
import 'package:areyoughost/services/invite_store.dart';
import 'package:areyoughost/services/ws_service.dart';
import 'package:areyoughost/ui/Invite_friend/Invite_host.dart';
import 'package:areyoughost/ui/widgets/buttons/accept_invite_button.dart';
import 'package:areyoughost/ui/widgets/buttons/reject_invite_button.dart';
import 'package:areyoughost/ui/widgets/icons/mail-icon.dart';
import 'package:bootstrap_icons/bootstrap_icons.dart';
import 'package:flutter/material.dart';

bool _gameInviteDialogShowing = false;

/// แสดงกล่องคำเชิญเข้าห้อง — เปิดเมื่อผู้เล่นกดไอคอนจดหมาย (มีคำเชิญค้างใน [InviteStore])
void showGameInviteDialog(BuildContext navContext, PendingInvite invite) {
  if (_gameInviteDialogShowing) return;
  if (!navContext.mounted) return;
  _gameInviteDialogShowing = true;
  showDialog<void>(
    context: navContext,
    barrierDismissible: false,
    builder: (dialogCtx) => _GameInviteDialog(
      navContext: navContext,
      invite: invite,
    ),
  ).whenComplete(() {
    _gameInviteDialogShowing = false;
  });
}

/// Mail / notification icon that shows a badge when there are pending invites.
/// Tapping it shows the first pending invite dialog from InviteStore.
class MailNotiIcon extends StatefulWidget {
  const MailNotiIcon({super.key});

  @override
  State<MailNotiIcon> createState() => _MailNotiIconState();
}

class _MailNotiIconState extends State<MailNotiIcon> {
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<PendingInvite>>(
      valueListenable: InviteStore.instance.invites,
      builder: (context, invites, _) {
        final hasInvite = invites.isNotEmpty;
        return IconButton(
          onPressed: () {
            if (hasInvite) {
              showGameInviteDialog(context, invites.first);
            } else {
              showEmptyMailDialog(context);
            }
          },
          icon: Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(
                hasInvite
                    ? BootstrapIcons.envelope_open_fill
                    : BootstrapIcons.envelope_fill,
                color: Colors.white,
                size: 25,
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
}

class _GameInviteDialog extends StatefulWidget {
  final BuildContext navContext;
  final PendingInvite invite;

  const _GameInviteDialog({
    required this.navContext,
    required this.invite,
  });

  @override
  State<_GameInviteDialog> createState() => _GameInviteDialogState();
}

class _GameInviteDialogState extends State<_GameInviteDialog> {
  bool _accepting = false;

  void _reject() {
    InviteStore.instance.remove(widget.invite.inviteCode);
    Navigator.pop(context);
  }

  Future<void> _accept() async {
    setState(() => _accepting = true);

    try {
      // Subscribe before sending accept to avoid missing a fast server reply.
      final replyFuture = WsService.instance.waitForAny(
        {'room.joined', 'error'},
        timeout: const Duration(seconds: 10),
      );
      WsService.instance.acceptInvite(widget.invite.inviteCode);
      InviteStore.instance.remove(widget.invite.inviteCode);
      final msg = await replyFuture;

      if (msg['type'] == 'error') {
        throw StateError('invite.accept failed');
      }

      final roomData = (msg['payload']?['room'] as Map<String, dynamic>?) ??
          (msg['payload'] as Map<String, dynamic>? ?? {});
      final room = RoomModel.fromJson(roomData);

      if (!mounted) return;
      Navigator.pop(context);
      if (!widget.navContext.mounted) return;
      Navigator.push(
        widget.navContext,
        MaterialPageRoute(
          builder: (_) => HostRoomScreen(
            initialRoom: room,
            showHostControls: false,
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      Navigator.pop(context);
      final messenger = ScaffoldMessenger.maybeOf(widget.navContext);
      messenger?.showSnackBar(
        const SnackBar(content: Text('ไม่สามารถเข้าร่วมห้องได้ ลองใหม่อีกครั้ง')),
      );
    } finally {
      if (mounted) setState(() => _accepting = false);
    }
  }

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
                    'คำเชิญเข้าห้อง',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 19,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    widget.invite.fromUsername,
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
                  const SizedBox(height: 8),
                  const Text(
                    'ไม่ต้องกรอกรหัสชวน — กดเข้าร่วมห้องได้เลย',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.black45, fontSize: 12),
                  ),
                  const SizedBox(height: 20),
                  if (_accepting)
                    const CircularProgressIndicator()
                  else
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        RejectInviteButton(onPressed: _reject),
                        const SizedBox(width: 18),
                        AcceptInviteButton(
                          onPressed: _accept,
                          label: 'เข้าร่วมห้อง',
                        ),
                      ],
                    ),
                ],
              ),
            ),
            if (!_accepting)
              Positioned(
                top: -6,
                right: -8,
                child: IconButton(
                  splashRadius: 20,
                  icon: const Icon(Icons.close, size: 30, color: Colors.black),
                  onPressed: _reject,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
