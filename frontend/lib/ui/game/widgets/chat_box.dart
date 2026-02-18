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
    return SizedBox(
      width: double.infinity,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: const Color(0x1F000000),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center, // 👈 Vertical center
            children: [
              const Text(
                'แชทออนไลน์',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 24, // 👈 Bigger
                  fontWeight: FontWeight.w700,
                  color: Colors.black,
                ),
              ),

              if (messages.isNotEmpty) ...[
                const SizedBox(height: 6),
                Expanded(
                  child: ListView.builder(
                    reverse: true,
                    padding: EdgeInsets.zero,
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final msg = messages[messages.length - 1 - index];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: RichText(
                          text: TextSpan(
                            style: const TextStyle(
                              fontSize: 13,
                              height: 1.35,
                              color: Colors.black,
                            ),
                            children: [
                              TextSpan(
                                text: '${msg.senderId} Player : ',
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
            ],
          ),
        ),
      ),
    );
  }
}
