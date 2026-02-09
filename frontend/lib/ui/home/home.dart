import 'package:flutter/material.dart'; 

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return 
    Scaffold(

      backgroundColor: Colors.black, // พื้นหลังรอบ ๆ
      body: Center(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // อัตราส่วนภาพ 390x844
            const double designWidth = 390;
            const double designHeight = 844;
            // final double aspectRatio = designWidth / designHeight;

            // double width = constraints.maxWidth;
            // double height = width / aspectRatio;

            // if (height > constraints.maxHeight) {
            //   height = constraints.maxHeight;
            //   width = height * aspectRatio;
            // }

            return SizedBox(
              width: designWidth,
              height: designHeight,
              child: Image.asset(
                'assets/images/ปกพื้นหลัง.jpg',
                fit: BoxFit.cover,
              ),
            );
          },
        ),
      ),
    );
  }
}
