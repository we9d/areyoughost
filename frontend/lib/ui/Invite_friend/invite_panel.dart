import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:areyoughost/services/ws_service.dart';

/// Bottom sheet invite panel — shown from WaitingRoomScreen for the host.
class InvitePanel extends StatefulWidget {
  final String inviteCode;

  const InvitePanel({super.key, required this.inviteCode});

  @override
  State<InvitePanel> createState() => _InvitePanelState();
}

class _InvitePanelState extends State<InvitePanel> {
  final _friendIdController = TextEditingController();
  bool _sent = false;
  String? _error;

  @override
  void dispose() {
    _friendIdController.dispose();
    super.dispose();
  }

  void _sendInvite() {
    final friendId = _friendIdController.text.trim();
    if (friendId.isEmpty) {
      setState(() => _error = 'กรุณากรอก ID เพื่อน');
      return;
    }
    WsService.instance.sendInvite(friendId, widget.inviteCode);
    setState(() {_sent = true; _error = null;});
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        top: 24,
        left: 24,
        right: 24,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF1A1A2E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),

          const Text(
            'ชวนเพื่อน',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
              fontFamily: 'Charmonman',
            ),
          ),
          const SizedBox(height: 16),

          // Invite Code Display
          GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: widget.inviteCode));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('คัดลอกรหัสแล้ว!')),
              );
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white24),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    widget.inviteCode,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 6,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Icon(Icons.copy, color: Colors.white54, size: 20),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Center(
            child: Text(
              'แชร์รหัสนี้ให้เพื่อน หรือส่งคำเชิญด้านล่าง',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ),

          const SizedBox(height: 20),
          const Divider(color: Colors.white12),
          const SizedBox(height: 12),

          // Direct Invite by Player ID
          const Text(
            'ส่งคำเชิญโดยตรง (Player ID)',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _friendIdController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Player ID ของเพื่อน',
                    hintStyle: const TextStyle(color: Colors.white38),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.08),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                onPressed: _sent ? null : _sendInvite,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7C3AED),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  _sent ? '✓' : 'ส่ง',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
          ],
          if (_sent) ...[
            const SizedBox(height: 8),
            const Text(
              'ส่งคำเชิญแล้ว! รอเพื่อนกดรับ...',
              style: TextStyle(color: Color(0xFF7C3AED), fontSize: 13),
            ),
          ],
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
