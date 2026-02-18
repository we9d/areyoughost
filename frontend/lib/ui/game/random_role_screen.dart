import 'dart:math';
import 'package:flutter/material.dart';
import 'role_result_card.dart';
import 'package:areyoughost/ui/game/game_screen.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

class RandomRoleScreen extends StatefulWidget {
  final String? roomId;
  const RandomRoleScreen({super.key, this.roomId});

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
          _showRoleResult();
        });
      }
    });

    _startRandom();
  }

  void _startRandom() {
    final random = Random();
    _finalIndex = random.nextInt(roles.length);
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

  void _showRoleResult() {
    final role = roles[_finalIndex];

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(24),
        child: RoleResultCard(
          roleName: role,
          description: 'คุณได้รับบทบาท $role',
          imagePath: 'assets/images/Login-Register.jpg',
          showDuration: const Duration(seconds: 5),
          onComplete: () {
            if (!mounted) return;
            Navigator.of(context, rootNavigator: true).pop();
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (_) => GameScreen(
                  roomId: widget.roomId ?? 'quick-room',
                  role: role,
                ),
              ),
            );
          },
        ),
      ),
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
