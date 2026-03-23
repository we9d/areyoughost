import 'package:flutter/material.dart';
import 'package:areyoughost/models/room_model.dart';
import 'package:areyoughost/services/invite_store.dart';
import 'package:areyoughost/services/ws_service.dart';
import 'package:areyoughost/services/session_manager.dart';
import 'package:areyoughost/ui/lobby/waiting_room_screen.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

class InviteInboxScreen extends StatefulWidget {
  const InviteInboxScreen({super.key});

  @override
  State<InviteInboxScreen> createState() => _InviteInboxScreenState();
}

class _InviteInboxScreenState extends State<InviteInboxScreen> {
  bool _loading = false;
  String? _errorMessage;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black.withOpacity(0.9),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'กล่องจดหมายคำเชิญ',
          style: TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.bold,
            fontFamily: 'Charmonman',
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Stack(
        children: [
          ValueListenableBuilder<List<PendingInvite>>(
            valueListenable: InviteStore.instance.invites,
            builder: (context, invites, _) {
              if (invites.isEmpty) {
                return const Center(
                  child: Text(
                    'ไม่มีคำเชิญในขณะนี้',
                    style: TextStyle(color: Colors.white54, fontSize: 18),
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: invites.length,
                itemBuilder: (context, index) {
                  final invite = invites[index];
                  return Card(
                    color: Colors.white10,
                    margin: const EdgeInsets.only(bottom: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      leading: CircleAvatar(
                        backgroundColor: Colors.purpleAccent,
                        child: Icon(PhosphorIcons.user(), color: Colors.white),
                      ),
                      title: Text(
                        '${invite.fromUsername} ชวนคุณเล่น',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.redAccent),
                            onPressed: () {
                              InviteStore.instance.remove(invite.inviteCode);
                            },
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            onPressed: _loading ? null : () => _acceptInvite(invite),
                            child: const Text('เข้าร่วม', style: TextStyle(color: Colors.white)),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
          if (_loading)
            Container(
              color: Colors.black54,
              child: const Center(child: CircularProgressIndicator(color: Colors.white)),
            ),
          if (_errorMessage != null && !_loading)
            Positioned(
              bottom: 40,
              left: 20,
              right: 20,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(color: Colors.white),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _acceptInvite(PendingInvite invite) async {
    setState(() { _loading = true; _errorMessage = null; });
    
    // Ensure connected
    if (!WsService.instance.isConnected) {
      final session = await SessionManager.getSession();
      final token = session?['token'];
      if (token == null) {
        setState(() { _loading = false; _errorMessage = 'กรุณาเข้าสู่ระบบก่อน'; });
        return;
      }
      try {
        await WsService.instance.connect(token);
        await WsService.instance.waitFor('auth.ok', timeout: const Duration(seconds: 5));
      } catch (_) {
        setState(() { _loading = false; _errorMessage = 'ไม่สามารถเชื่อมต่อ server ได้'; });
        return;
      }
    }

    // Send accept message
    WsService.instance.acceptInvite(invite.inviteCode);

    try {
      final msg = await WsService.instance.waitFor('room.joined', timeout: const Duration(seconds: 10));
      final room = RoomModel.fromJson((msg['payload']['room'] as Map<String, dynamic>?) ?? msg['payload']);
      
      // Remove from store
      InviteStore.instance.remove(invite.inviteCode);

      if (!mounted) return;
      setState(() => _loading = false);
      
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => WaitingRoomScreen(initialRoom: room, isHost: false)),
      );
    } catch (_) {
      setState(() {
        _loading = false;
        _errorMessage = 'เข้าร่วมห้องไม่สำเร็จ (โค้ดอาจหมดอายุหรือห้องเต็ม)';
      });
    }
  }
}
