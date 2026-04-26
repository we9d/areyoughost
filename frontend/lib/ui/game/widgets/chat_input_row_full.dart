import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:areyoughost/ui/game/dialogs/skill_popup_choice.dart';
import 'package:areyoughost/ui/game/dialogs/skill_popup_result.dart';

class ChatInputRowFull extends StatefulWidget {
  final VoidCallback onRoleInfoTap;
  final ValueChanged<String> onSend;

  const ChatInputRowFull({
    super.key,
    required this.onRoleInfoTap,
    required this.onSend,
  });

  @override
  State<ChatInputRowFull> createState() => _ChatInputRowFullState();
}

class _ChatInputRowFullState extends State<ChatInputRowFull> {
  final TextEditingController _controller = TextEditingController();

  void _handleSend() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    widget.onSend(text);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [

            /// ROLE
            IconButton(
              iconSize: 25,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              icon: Icon(
                PhosphorIcons.maskHappy(),
                color: Colors.white,
              ),
              onPressed: widget.onRoleInfoTap,
            ),

            const SizedBox(width: 6),

            /// CHAT
            IconButton(
              iconSize: 25,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              icon: Icon(
                PhosphorIcons.wechatLogo(),
                color: Colors.white,
              ),
              onPressed: () {},
            ),

            const SizedBox(width: 6),

            /// SKILL
            GestureDetector(
              onTap: () {
                showDialog(
                  context: context,
                  barrierColor: Colors.black54,
                  builder: (_) => SkillPopupChoice(
                    skill1Name: "สกิลตาวิเศษ",
                    skill1Description: "เลือกผู้เล่น 1 คนเพื่อทำการตรวจฝ่าย",
                    skill1Image: "assets/images/skill_eye.png",
                    skill2Name: "สกิลชุบชีวิต",
                    skill2Description: "ฟื้นคืนชีพผู้เล่นที่ตายแล้ว",
                    skill2Image: "assets/images/skill_heal.png",
                    onSkill1: () {
                      Navigator.pop(context);
                      showDialog(
                        context: context,
                        barrierColor: Colors.black54,
                        builder: (_) => const SkillPopupResult(
                          skillName: "สกิลตาวิเศษ",
                          skillImage: "assets/images/skill_eye.png",
                          resultMessage: '1 น้องข้าว หมายเลขฝ่าย\n“ผี”',
                        ),
                      );
                    },
                    onSkill2: () {
                      Navigator.pop(context);
                      showDialog(
                        context: context,
                        barrierColor: Colors.black54,
                        builder: (_) => const SkillPopupResult(
                          skillName: "สกิลชุบชีวิต",
                          skillImage: "assets/images/skill_heal.png",
                          resultMessage: 'ชุบชีวิตผู้เล่นสำเร็จ',
                        ),
                      );
                    },
                    onClose: () => Navigator.pop(context),
                  ),
                );
              },
              child: SvgPicture.asset(
                'assets/icons/skill-icon.svg',
                width: 25,
                height: 25,
                colorFilter: const ColorFilter.mode(
                  Colors.white,
                  BlendMode.srcIn,
                ),
              ),
            ),

            const SizedBox(width: 10),

            Expanded(child: _buildInput()),
          ],
        ),
      ),
    );
  }

  Widget _buildInput() {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      alignment: Alignment.center,
      child: TextField(
        controller: _controller,
        textInputAction: TextInputAction.send,
        onSubmitted: (_) => _handleSend(),
        decoration: const InputDecoration(
          hintText: "ส่งข้อความ",
          hintStyle: TextStyle(
            color: Colors.grey,
            fontSize: 17,
          ),
          border: InputBorder.none,
          contentPadding: EdgeInsets.only(bottom: 8),
        ),
      ),
    );
  }
}