import 'package:flutter/material.dart';
import 'package:bootstrap_icons/bootstrap_icons.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black, // พื้นหลังรอบ ๆ
      body: Center(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // อัตราส่วนภาพ 390x844
            const double designWidth = 390;
            const double designHeight = 844;

            return SizedBox(
              width: designWidth,
              height: designHeight,
              child: Stack(
                children: [
                  // พื้นหลัง
                  Image.asset(
                    'assets/images/ปกพื้นหลัง.jpg',
                    fit: BoxFit.cover,
                    width: designWidth,
                    height: designHeight,
                  ),

                  // icon มุมขวาบน
                  Positioned(
                    top: 48,
                    right: 10,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          icon: const Icon(
                            BootstrapIcons.envelope_fill,
                            color: Colors.white,
                            size: 25,
                          ),
                          onPressed: () {
                            showDialog(
                              context: context,
                              barrierDismissible: false, // กดนอกกล่องไม่ปิด
                              builder: (context) {
                                return Dialog(
                                  backgroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: SizedBox(
                                    width: 358,
                                    height: 187,
                                    child: Stack(
                                      children: [
                                        // ปุ่มกากบาท มุมขวาบน
                                        Positioned(
                                          top: 8,
                                          right: 8,
                                          child: IconButton(
                                            icon: const Icon(
                                              Icons.close,
                                              size: 20,
                                              color: Colors.black,
                                            ),
                                            onPressed: () {
                                              Navigator.pop(context);
                                            },
                                          ),
                                        ),

                                        // เนื้อหา
                                        Center(
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const SizedBox(height: 8),

                                              Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                children: [
                                                  // เส้นซ้าย
                                                  Container(
                                                    width: 60,
                                                    height: 0.8,
                                                    color: Colors.black,
                                                  ),

                                                  const SizedBox(width: 12),

                                                  const Text(
                                                    'ไม่มีคำเชิญชวน',
                                                    textAlign: TextAlign.center,
                                                    style: TextStyle(
                                                      fontSize: 20,
                                                      color: Color.fromARGB(
                                                        255,
                                                        12,
                                                        0,
                                                        0,
                                                      ),
                                                    ),
                                                  ),

                                                  const SizedBox(width: 12),

                                                  // เส้นขวา
                                                  Container(
                                                    width: 60,
                                                    height: 0.8,
                                                    color: Colors.black,
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        ),

                        const SizedBox(width: 7),

                        IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          icon: const Icon(
                            BootstrapIcons.person_plus_fill,
                            color: Colors.white,
                            size: 25,
                          ),
                          onPressed: () {
                            showDialog(
                              context: context,
                              barrierDismissible: false, // กดนอกกล่องไม่ปิด
                              builder: (context) {
                                return Dialog(
                                  backgroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: SizedBox(
                                    width: 500,
                                    height: 550,
                                    child: Stack(
                                      children: [
                                        // ปุ่มกากบาท มุมขวาบน
                                        Positioned(
                                          top: 8,
                                          right: 8,
                                          child: IconButton(
                                            icon: const Icon(
                                              Icons.close,
                                              size: 20,
                                              color: Colors.black,
                                            ),
                                            onPressed: () {
                                              Navigator.pop(context);
                                            },
                                          ),
                                        ),
                                        // เนื้อหา
                                        Align(
                                          alignment: Alignment.topCenter,
                                          child: Padding(
                                            padding: const EdgeInsets.only(
                                              top: 16,
                                            ),
                                            child: const Text(
                                              'เพื่อน',
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                fontSize: 20,
                                                fontWeight: FontWeight.bold,
                                                color: Color.fromARGB(
                                                  255,
                                                  12,
                                                  0,
                                                  0,
                                                ),
                                                decoration: TextDecoration
                                                    .underline, // เส้นใต้
                                                decorationThickness: 1.5,
                                                decorationColor: Colors.black,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        ),

                        const SizedBox(width: 5),

                        IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          icon: const Icon(
                            BootstrapIcons.gear,
                            color: Colors.white,
                            size: 25,
                          ),
                          onPressed: () {
                            showDialog(
                              context: context,
                              barrierDismissible: false, // กดนอกกล่องไม่ปิด
                              builder: (context) {
                                return Dialog(
                                  backgroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: SizedBox(
                                    width: 360,
                                    height: 200,
                                    child: Stack(
                                      children: [
                                        // ปุ่มกากบาท มุมขวาบน
                                        Positioned(
                                          top: 8,
                                          right: 8,
                                          child: IconButton(
                                            icon: const Icon(
                                              Icons.close,
                                              size: 20,
                                              color: Colors.black,
                                            ),
                                            onPressed: () {
                                              Navigator.pop(context);
                                            },
                                          ),
                                        ),
                                        // เนื้อหา
                                        Align(
                                          alignment: Alignment.topCenter,
                                          child: Padding(
                                            padding: const EdgeInsets.only(
                                              top: 16,
                                            ),
                                            child: const Text(
                                              'การตั้งค่า',
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                fontSize: 20,
                                                fontWeight: FontWeight.bold,
                                                color: Color.fromARGB(
                                                  255,
                                                  12,
                                                  0,
                                                  0,
                                                ),
                                                decoration: TextDecoration
                                                    .underline, // เส้นใต้
                                                decorationThickness: 1.5,
                                                decorationColor: Colors.black,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
