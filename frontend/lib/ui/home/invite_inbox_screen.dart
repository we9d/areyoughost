import 'package:flutter/material.dart';
import 'package:areyoughost/models/room_model.dart';
import 'package:areyoughost/services/invite_store.dart';
import 'package:areyoughost/services/session_manager.dart';
import 'package:areyoughost/ui/game/game_screen.dart';
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
    setState(() { 
      _loading = false; 
      _errorMessage = 'ระบบคำเชิญเดิม (WS) ถูกปิดใช้งานแล้ว กรุณาใช้ระบบใหม่ผ่าน TCP'; 
    });
  }
}
