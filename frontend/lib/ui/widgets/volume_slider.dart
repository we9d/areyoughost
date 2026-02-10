import 'package:flutter/material.dart';

class VolumeSlider extends StatelessWidget {
  final double value;
  final ValueChanged<double> onChanged;

  const VolumeSlider({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'เสียงประกอบ',
          style: TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: Colors.black,
            inactiveTrackColor: Colors.grey.shade300,
            thumbColor: Colors.black,
            overlayColor: Colors.black.withOpacity(0.2),
            trackHeight: 2,
            
            thumbShape: const RoundSliderThumbShape(
              enabledThumbRadius: 8, // 👈 ขนาดปุ่มเลื่อน
              pressedElevation: 2,
            ),
          ),
          child: Slider(value: value, min: 0, max: 100, onChanged: onChanged),
        ),
      ],
    );
  }
}
