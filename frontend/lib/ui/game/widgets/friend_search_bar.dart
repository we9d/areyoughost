import 'package:flutter/material.dart';
import 'package:areyoughost/ui/widgets/icons/friend_search_icon.dart';

class FriendSearchBar extends StatelessWidget {
  final TextEditingController? controller;
  final String hintText;
  final VoidCallback? onSearchPressed;

  const FriendSearchBar({
    super.key,
    this.controller,
    this.hintText = 'เพิ่มเพื่อนด้วยชื่อบัญชีผู้ใช้งาน',
    this.onSearchPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 46,
      decoration: BoxDecoration(
        color: const Color(0xFFF7F7F7),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.22),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              style: const TextStyle(
                color: Colors.black,
                fontSize: 16,
              ),
              decoration: InputDecoration(
                border: InputBorder.none,
                isCollapsed: true,
                contentPadding: const EdgeInsets.only(
                  left: 18,
                  right: 10,
                  top: 14,
                  bottom: 14,
                ),
                hintText: hintText,
                hintStyle: const TextStyle(
                  color: Color(0xFF9A9A9A),
                  fontSize: 14,
                ),
              ),
            ),
          ),
          SizedBox(
            width: 52,
            height: 46,
            child: InkWell(
              borderRadius: BorderRadius.circular(24),
              onTap: onSearchPressed,
              child: const Center(
                child: FriendSearchIcon(
                  size: 30,
                  color: Colors.black,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}