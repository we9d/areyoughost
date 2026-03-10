import 'package:areyoughost/ui/widgets/buttons/decoration/shadow.dart';
import 'package:flutter/material.dart';

class RulesButton extends StatelessWidget {
  const RulesButton({super.key});

  void _showRules(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => const _RulesDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      child: Shadow(
        height: 60,
        width: 150,
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color.fromARGB(255, 34, 53, 72), Color(0xFF3A5A7A)],
          stops: [0.0, 1.25],
        ),
        onPressed: () => _showRules(context),
        child: const Text(
          "กติกา",
          style: TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

class _RulesDialog extends StatefulWidget {
  const _RulesDialog();

  @override
  State<_RulesDialog> createState() => _RulesDialogState();
}

class _RulesDialogState extends State<_RulesDialog> {
  final ScrollController _scrollController = ScrollController();

  final List<String> _rules = const [
    'ผู้เล่นสามารถรับรู้บทบาทเฉพาะของตนเองเท่านั้น',
    'ในช่วงกลางคืนผู้เล่นสามารถใช้บทบาทที่ตัวเองได้รับ ทำหน้าที่ต่างกันไป โดยฝ่ายผีจะทำการโหวตชาวบ้านออกเช่นกัน รวมไปถึงบทพิเศษ เช่น ฆาตกรต่อเนื่องและเจ้ากรรมนายเวรจะทำการสังหารชาวบ้านหรือผี',
    'ในช่วงกลางวันฝ่ายชาวบ้านจะทำการปรึกษาหารือ เพื่อทำการหาผี และบทบาทพิเศษ เพื่อทำการกำจัด',
    'เมื่อหมดเวลาช่วงกลางวัน ผู้เล่นทุกคนจะสามารถโหวต หรือทำการสังหารผู้ต้องสงสัย',
    'ผู้เล่นฝ่ายชาวบ้านสามารถชนะได้ก็ต่อเมื่อทำการกำจัดฝ่ายผี หรือบทบาทพิเศษจนครบ',
    'ผู้เล่นฝ่ายผีสามารถชนะได้ก็ต่อเมื่อมีผู้เล่นฝ่ายผีมีจำนวนเท่ากับผู้เล่นฝ่ายชาวบ้าน',
    'ผู้เล่นบทบาทพิเศษสามารถชนะได้ตามเงื่อนไขเฉพาะ',
  ];

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
              top: 10,
              right: 10,
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
              padding: const EdgeInsets.fromLTRB(22, 20, 18, 22),
              child: Column(
                children: [
                  const SizedBox(height: 4),
                  const Text(
                    'กติกา',
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      decoration: TextDecoration.underline,
                      decorationColor: Colors.black,
                      decorationThickness: 1.5,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Expanded(
                    child: RawScrollbar(
                      controller: _scrollController,
                      thumbVisibility: true,
                      trackVisibility: true,
                      thickness: 4,
                      radius: const Radius.circular(12),
                      thumbColor: const Color(0xFF5A5A5A),
                      trackColor: const Color(0xFFD0D0D0),
                      trackBorderColor: Colors.transparent,
                      crossAxisMargin: 2,
                      mainAxisMargin: 4,
                      child: SingleChildScrollView(
                        controller: _scrollController,
                        padding: const EdgeInsets.only(right: 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: List.generate(
                            _rules.length,
                            (index) => Padding(
                              padding: const EdgeInsets.only(bottom: 14),
                              child: Text(
                                '${index + 1}. ${_rules[index]}',
                                style: const TextStyle(
                                  color: Colors.black,
                                  fontSize: 20,
                                  height: 1.5,
                                ),
                              ),
                            ),
                          ),
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