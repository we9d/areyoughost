import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:areyoughost/ui/game/widgets/roles_card.dart';
/// ===============================================================
/// ChatInputRow
/// ---------------------------------------------------------------
/// แถบ input ด้านล่างของหน้าจอเกม
///
/// ปุ่มที่มี:
/// - ปุ่มดูบทบาท
/// - ปุ่มเปิดแชท
/// - ปุ่มใช้สกิล
/// - ช่องพิมพ์ข้อความ
///
/// Backend ต้องเชื่อม:
/// widget.onSend(text)
///
/// เมื่อผู้เล่นกด send → backend จะต้องส่งข้อความไปยังระบบ chat server
/// ===============================================================

class ChatInputRow extends StatefulWidget {
  final VoidCallback onRoleInfoTap;
  final VoidCallback onSkillTap;
  final ValueChanged<String> onSend;

  const ChatInputRow({
    super.key,
    required this.onRoleInfoTap,
    required this.onSkillTap,
    required this.onSend,
  });

  @override
  State<ChatInputRow> createState() => _ChatInputRowState();
}

class _ChatInputRowState extends State<ChatInputRow> {

  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// ===============================================================
  /// ส่งข้อความไปยัง backend
  /// ===============================================================
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

            /// ===================================================
            /// ICON SECTION
            /// ใช้ Row แยกเพื่อลดปัญหา overflow
            /// ===================================================
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [

                /// ปุ่มบทบาท
                IconButton(
                  iconSize: 25,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: Icon(
                    PhosphorIcons.maskHappy(),
                    color: Colors.white,
                  ),
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (_) => RolesDialog(),
                    );
                  },
                ),

                const SizedBox(width: 6),
                /// ปุ่มแชท
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

                /// ปุ่มสกิล
                GestureDetector(
                  onTap: widget.onSkillTap,

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
              ],
            ),

            /// ===================================================
            /// TEXT INPUT
            /// Expanded ทำให้ช่องพิมพ์กินพื้นที่ที่เหลือ
            /// ===================================================
            Expanded(
              child: Container(

                height: 36,

                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                ),

                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                ),

                alignment: Alignment.center,

                child: TextField(
                  controller: _controller,

                  textInputAction: TextInputAction.send,

                  /// ส่งข้อความเมื่อกด enter
                  onSubmitted: (_) => _handleSend(),

                  decoration: const InputDecoration(
                    hintText: "ส่งข้อความ",

                    hintStyle: TextStyle(
                      fontSize: 13,
                      color: Colors.black38,
                    ),

                    border: InputBorder.none,
                    isCollapsed: true,
                  ),

                  style: const TextStyle(
                    fontSize: 13,
                    color: Colors.black,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}