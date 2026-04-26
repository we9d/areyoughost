import 'package:flutter/material.dart';
import 'package:areyoughost/models/mock_models.dart';

class ChatBox extends StatelessWidget {
  final List<ChatMessage> messages;
  final ScrollController? scrollController;
  final String? historyLabel;

  const ChatBox({
    super.key,
    required this.messages,
    this.scrollController,
    this.historyLabel,
  });

  static const Color _joinedColor = Color(0xFF4DD6C9);
  static const Color _leftColor = Color(0xFFFF6B6B);

  Color _messageColor(ChatMessage msg) {
    final text = msg.message;
    final isSystem = msg.senderName == 'ระบบ' || msg.senderId == '0';
    if (!isSystem) return Colors.white;

    // Match game status announcements to the same palette as joined/left feed:
    // positive/neutral -> joined color, negative (death/leave-like) -> left color.
    final isNegative =
        text.contains('เสียชีวิต') || text.contains('ตาย') || text.contains('โดนฝ่ายผีฆ่า');
    return isNegative ? _leftColor : _joinedColor;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(22),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1F000000),
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (historyLabel != null && historyLabel!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    historyLabel!,
                    style: const TextStyle(
                      fontFamily: 'Charmonman',
                      fontSize: 12,
                      color: Color(0xFF4DD6C9),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              Expanded(
                child: ScrollConfiguration(
                  behavior: const MaterialScrollBehavior().copyWith(scrollbars: false),
                  child: ListView.builder(
                    controller: scrollController,
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final msg = messages[index];
                      final isSystem = msg.senderName == 'ระบบ' || msg.senderId == '0';
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: RichText(
                          text: TextSpan(
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontFamily: 'Charmonman',
                            ),
                            children: [
                              if (!isSystem) TextSpan(text: '${msg.senderId} '),
                              if (!isSystem) TextSpan(text: '${msg.senderName} '),
                              TextSpan(
                                text: msg.message,
                                style: TextStyle(
                                  fontFamily: 'Charmonman',
                                  color: _messageColor(msg),
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
