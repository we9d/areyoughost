import 'package:flutter/material.dart';
import 'package:areyoughost/models/mock_models.dart';

class ChatBox extends StatelessWidget {
  final List<ChatMessage> messages;

  const ChatBox({
    super.key,
    required this.messages,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.10),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        children: [
          /// 🔹 CONTENT
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                /// Header
                const Text(
                  'แชทออนไลน์',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1A1A1A),
                  ),
                ),

                const SizedBox(height: 8),

                /// Message list
                Expanded(
                  child: messages.isEmpty
                      ? const Center(
                          child: Text(
                            'ยังไม่มีข้อความ',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.black45,
                            ),
                          ),
                        )
                      : ListView.builder(
                          reverse: true, // ✅ แชทใหม่อยู่ล่าง
                          padding: EdgeInsets.zero,
                          itemCount: messages.length,
                          itemBuilder: (context, index) {
                            final msg =
                                messages[messages.length - 1 - index];

                            return Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 3),
                              child: RichText(
                                text: TextSpan(
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Colors.black,
                                    height: 1.35,
                                  ),
                                  children: [
                                    TextSpan(
                                      text:
                                          '${msg.senderId} ${msg.senderName}: ',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    TextSpan(text: msg.message),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),

          /// 🔹 INNER SHADOW (เหมือน Figma)
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withOpacity(0.10),
                      Colors.transparent,
                      Colors.black.withOpacity(0.08),
                    ],
                    stops: const [0.0, 0.18, 1.0],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
