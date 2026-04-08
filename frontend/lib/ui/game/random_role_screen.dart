import 'dart:math';
import 'package:flutter/material.dart';
import 'role_result_card.dart';
import 'package:areyoughost/ui/game/game_screen.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:areyoughost/services/game_data_service.dart';

class RandomRoleScreen extends StatefulWidget {
  final String? roomId;
  final String assignedRole;
  
  const RandomRoleScreen({
    super.key, 
    this.roomId, 
    required this.assignedRole,
  });

  @override
  State<RandomRoleScreen> createState() => _RandomRoleScreenState();
}

class _RandomRoleScreenState extends State<RandomRoleScreen>
    with SingleTickerProviderStateMixin {
  static const List<String> roles = [
    'ชาวบ้าน',
    'ร่างทรง',
    'แพทย์',
    'ทหาร',
    'ตำรวจ',
    'พระธุดงค์',
    'หมอผีคุณไสย',
    'สัปเหร่อ',
    'คนดวงซวย',
    'ผีปอบ',
    'ผีกระสือใหญ่',
    'ผีตายโหง',
    'ผีเปรต',
    'หมอผีดำ',
    'ฆาตกรต่อเนื่อง',
    'เจ้ากรรมนายเวร',
  ];

  late final AnimationController _controller;
  late final ScrollController _scrollController;
  int _finalIndex = 0;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..addListener(_onAnimate);

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        Future.delayed(const Duration(seconds: 2), () {
          if (!mounted) return;
          _showResultCard();
        });
      }
    });

    _startRandom();
  }

  void _startRandom() {
    final random = Random();
    final roleData = GameDataService.getRoleByCode(widget.assignedRole);
    final targetName = roleData?.roleName ?? widget.assignedRole;
    int targetIndex = roles.indexOf(targetName);
    if (targetIndex == -1) targetIndex = 0;
    
    // Add extra full rotations so the spin takes time before landing on the target
    _finalIndex = targetIndex; 
    
    _controller.forward(from: 0);
  }

  void _onAnimate() {
    if (!_scrollController.hasClients) return;

    const itemHeight = 48.0;
    final maxScroll =
        roles.length * itemHeight * 6 + _finalIndex * itemHeight;

    final value =
        Curves.easeOut.transform(_controller.value) * maxScroll;

    _scrollController.jumpTo(value);
  }

  void _onPlayerTap() {
    debugPrint('Players icon tapped');
  }


  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _showResultCard() {
    final role = GameDataService.getRoleByCode(widget.assignedRole);
    
    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, anim1, anim2) {
        return Center(
          child: Material(
            color: Colors.transparent,
            child: RoleResultCard(
              roleName: role?.roleName ?? widget.assignedRole,
              description: role?.description ?? 'ค้นหาผีปอบและโหวตออก',
              imagePath: role?.imagePath ?? 'assets/images/V01.jpg',
              onComplete: () {
                Navigator.of(context).pop(); // dialog
                Navigator.of(context).pop(); // screen
              },
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // ===== BG =====
          Positioned.fill(
            child: Image.asset(
              'assets/images/RandomRoleBg.jpg',
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
            ),
          ),

          // ===== DARK OVERLAY =====
          Positioned.fill(
            child: Container(
              color: Colors.black.withOpacity(0.35),
            ),
          ),

          // ===== ICON =====
          Positioned(
            top: 24,
            right: 6,
            child: SafeArea(
              child: GestureDetector(
                onTap: _onPlayerTap,
                behavior: HitTestBehavior.opaque,
                child: SizedBox(
                  width: 32,
                  child: Icon(
                    PhosphorIcons.usersThree(),
                    size: 32.0,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),


          // ===== CONTENT =====
          SafeArea(
            child: Column(
              children: [
                const Spacer(),

                // ===== TITLE =====
                const Text(
                  'สุ่มบทบาท',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    shadows: [
                      Shadow(
                        blurRadius: 6,
                        color: Colors.black87,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // ===== SLOT BOX =====
                Center(
                  child: Container(
                    width: 260,
                    height: 48,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.arrow_forward_ios,
                          size: 16,
                          color: Colors.black,
                        ),
                        const SizedBox(width: 12),

                        // ===== TEXT =====
                        Expanded(
                          child: ClipRect(
                            child: ListView.builder(
                              controller: _scrollController,
                              physics:
                                  const NeverScrollableScrollPhysics(),
                              itemCount: roles.length * 20,
                              itemBuilder: (_, i) {
                                final role = roles[i % roles.length];
                                return SizedBox(
                                  height: 48,
                                  child: Center(
                                    child: Text(
                                      role,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.black,
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                        const SizedBox(width: 28), 
                      ],
                    ),
                  ),
                ),

                const Spacer(flex: 2),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
