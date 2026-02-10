import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

class UsernameField extends StatelessWidget {
  final TextEditingController controller;
  final bool canEdit;
  final VoidCallback onEditPressed;

  const UsernameField({
    super.key,
    required this.controller,
    required this.canEdit,
    required this.onEditPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'ชื่อผู้ใช้งาน',
          style: TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 6),
            ],
          ),
          child: TextField(
            controller: controller,
            readOnly: true, //ล็อกไว้ตลอด
            cursorWidth: 1,
            textAlign: TextAlign.start,
            style: TextStyle(
              color: canEdit ? Colors.black : Colors.black,
              fontSize: 14,
            ),

            decoration: InputDecoration(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 5,
                vertical: 18,
              ),
              border: InputBorder.none,
              suffixIcon: IconButton(
                icon: Icon(
                  PhosphorIcons.pencilSimpleLine(),
                  size: 20,
                  color: Colors.grey.shade700,
                ),
                onPressed: onEditPressed, // 👉 เปิด popup ใหม่
              ),
            ),
          ),
        ),
      ],
    );
  }
}
