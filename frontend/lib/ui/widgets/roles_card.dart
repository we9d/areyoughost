import 'package:areyoughost/ui/widgets/buttons/decoration/shadow.dart';
import 'package:areyoughost/ui/widgets/role_dropdown_card.dart';
import 'package:flutter/material.dart';

class RolesButton extends StatelessWidget {
  const RolesButton({super.key});

  void _showRoles(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => const _RolesDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Shadow(
      height: 60,
      width: 150,
      gradient: const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color.fromARGB(255, 34, 53, 72), Color(0xFF3A5A7A)],
        stops: [0.0, 1.25],
      ),
      onPressed: () => _showRoles(context),
      child: const Text(
        'บทบาท',
        style: TextStyle(
          color: Colors.white,
          fontSize: 24,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _RolesDialog extends StatefulWidget {
  const _RolesDialog();

  @override
  State<_RolesDialog> createState() => _RolesDialogState();
}

class _RolesDialogState extends State<_RolesDialog> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Container(
        width: 360,
        height: 580,
        decoration: BoxDecoration(
          color: const Color(0xFFF2F2F2),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Stack(
          children: [
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                icon: const Icon(
                  Icons.close,
                  color: Colors.black,
                  size: 34,
                ),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 14, 18),
              child: Column(
                children: [
                  const SizedBox(height: 2),
                  const Text(
                    'บทบาท',
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      decoration: TextDecoration.underline,
                      decorationColor: Colors.black,
                      decorationThickness: 1.5,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: RawScrollbar(
                      controller: _scrollController,
                      thumbVisibility: true,
                      trackVisibility: true,
                      thickness: 4,
                      radius: const Radius.circular(12),
                      thumbColor: Color(0xFF4A4A4A),
                      trackColor: Color(0xFFD1D1D1),
                      trackBorderColor: Colors.transparent,
                      crossAxisMargin: 2,
                      mainAxisMargin: 2,
                      child: SingleChildScrollView(
                        controller: _scrollController,
                        padding: const EdgeInsets.only(right: 10),
                        child: const Column(
                          children: [
                            RoleDropdownCard(
                              imagePath: 'assets/images/V01.jpg',
                              roleName: 'ชาวบ้าน',
                              team: 'ชาวบ้าน',
                              aura: 'ดี',
                              description:
                                  'ไม่มีพลังพิเศษ ทำหน้าที่พูดคุย วิเคราะห์ และโหวตกลางตอนวัน',
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}