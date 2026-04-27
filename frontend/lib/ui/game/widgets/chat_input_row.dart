import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:flutter_svg/flutter_svg.dart';
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
  final VoidCallback onChatTap;
  final VoidCallback onSkillTap;
  final ValueChanged<String> onSend;
  final bool canSend;
  /// When false (e.g. player is dead), skill icon is dimmed and taps are ignored.
  final bool canUseSkills;
  final String? disabledHint;

  const ChatInputRow({
    super.key,
    required this.onRoleInfoTap,
    required this.onChatTap,
    required this.onSkillTap,
    required this.onSend,
    this.canSend = true,
    this.canUseSkills = true,
    this.disabledHint,
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
                  onPressed: widget.onRoleInfoTap,
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

                  onPressed: widget.onChatTap,
                ),

                const SizedBox(width: 6),

                /// ปุ่มสกิล
                Opacity(
                  opacity: widget.canUseSkills ? 1 : 0.35,
                  child: IgnorePointer(
                    ignoring: !widget.canUseSkills,
                    child: GestureDetector(
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
                  enabled: widget.canSend,
                  textAlignVertical: TextAlignVertical.center,

                  textInputAction: TextInputAction.send,

                  /// ส่งข้อความเมื่อกด enter
                  onSubmitted: (_) {
                    if (widget.canSend) _handleSend();
                  },

                  decoration: InputDecoration(
                    hintText: widget.canSend
                        ? "ส่งข้อความ"
                        : (widget.disabledHint ?? "ยังไม่สามารถพิมพ์ได้ในเฟสนี้"),

                    hintStyle: const TextStyle(
                      fontSize: 13,
                      color: Colors.black38,
                    ),
                    suffixIcon: IconButton(
                      tooltip: 'ส่งข้อความ',
                      onPressed: widget.canSend ? _handleSend : null,
                      icon: Icon(
                        PhosphorIcons.paperPlaneRight(),
                        size: 18,
                        color: widget.canSend ? Colors.black54 : Colors.black26,
                      ),
                    ),
                    suffixIconConstraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    border: InputBorder.none,
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