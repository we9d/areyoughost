import 'package:flutter/material.dart';

class Shadow extends StatelessWidget {
  final VoidCallback onPressed;
  final LinearGradient gradient;
  final Widget child;
  final double width ;
  final double height ;

  const Shadow({
    super.key,
    required this.onPressed,
    required this.gradient,
    required this.child,
    required this.height,
    required this.width,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onPressed,
        child: Container(
          width: width, //button width
          height: height, //button height
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(30)),
          child: Stack(
            //โค้ดมาก่อนได้อยู่หลังสุด
            children: [
              // INNER SHADOW
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(25),
                      gradient: gradient,
                    ),
                  ),
                ),
              ),
              // ตัวปุ่มสีจริง
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(30),
                ),
                alignment: Alignment.center,
                child: child,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
