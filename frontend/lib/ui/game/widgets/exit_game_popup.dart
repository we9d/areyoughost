import 'package:flutter/material.dart' as m;

class ExitGamePopup extends m.StatelessWidget {
  final m.VoidCallback? onConfirm;
  const ExitGamePopup({super.key, this.onConfirm});

  @override
  m.Widget build(m.BuildContext context) {
    return m.Dialog(
      backgroundColor: m.Colors.transparent,
      child: m.Container(
        width: 358,
        height: 180,
        padding: const m.EdgeInsets.fromLTRB(24, 22, 24, 22),
        decoration: m.BoxDecoration(
          color: const m.Color(0xFFEFEFEF),
          borderRadius: m.BorderRadius.circular(24),
          boxShadow: const [
            m.BoxShadow(
              color: m.Colors.black26,
              blurRadius: 18,
              offset: m.Offset(0, 8),
            )
          ],
        ),
        child: m.Column(
          children: [

            /// CLOSE BUTTON
            m.Align(
              alignment: m.Alignment.topRight,
              child: m.MouseRegion(
                cursor: m.SystemMouseCursors.click,
                child: m.GestureDetector(
                  onTap: () => m.Navigator.pop(context),
                  child: const m.Icon(
                    m.Icons.close,
                    size: 22,
                    color: m.Colors.black,
                  ),
                ),
              ),
            ),

            const m.SizedBox(height: 6),

            /// TEXT
            const m.Text(
              "คุณต้องการออกจากเกมหรือไม่?",
              textAlign: m.TextAlign.center,
              style: m.TextStyle(
                fontSize: 19,
                fontWeight: m.FontWeight.w700,
                color: m.Colors.black,
              ),
            ),

            const m.Spacer(),

            /// EXIT BUTTON
            m.MouseRegion(
              cursor: m.SystemMouseCursors.click,
              child: m.GestureDetector(
                onTap: () {
                  if (onConfirm != null) {
                    onConfirm!();
                  } else {
                    m.Navigator.pop(context);
                    m.Navigator.pop(context);
                  }
                },
                child: m.Container(
                  width: 160,
                  height: 48,
                  alignment: m.Alignment.center,
                  decoration: m.BoxDecoration(
                    gradient: const m.LinearGradient(
                      begin: m.Alignment.topCenter,
                      end: m.Alignment.bottomCenter,
                      colors: [
                        m.Color(0xFFC51010),
                        m.Color(0xFF6A1F2B),
                      ],
                      stops: [0.0, 1.0],
                    ),
                    borderRadius: m.BorderRadius.circular(26),
                    boxShadow: const [
                      m.BoxShadow(
                        color: m.Colors.black26,
                        blurRadius: 10,
                        offset: m.Offset(0, 4),
                      )
                    ],
                  ),
                  child: const m.Text(
                    "ออกจากเกม",
                    style: m.TextStyle(
                      color: m.Colors.white,
                      fontSize: 18,
                      fontWeight: m.FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),

            const m.SizedBox(height: 6),
          ],
        ),
      ),
    );
  }
}