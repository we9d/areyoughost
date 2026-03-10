import 'package:flutter/material.dart';

class SkillOption {
  final String name;
  final String description;
  final String image;

  SkillOption({
    required this.name,
    required this.description,
    this.image = 'assets/icons/investigate.png', // Add a default placeholder
  });
}

class SkillSelectDialog extends StatelessWidget {
  final List<SkillOption> skills;
  final Function(SkillOption) onSelect;

  const SkillSelectDialog({
    super.key,
    required this.skills,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 358,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xFFF4F4F4),
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              blurRadius: 24,
              offset: const Offset(0, 10),
              color: Colors.black.withOpacity(0.25),
            )
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            /// CLOSE BUTTON
            Align(
              alignment: Alignment.topRight,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: const Icon(
                    Icons.close,
                    color: Colors.black,
                  ),
                ),
              ),
            ),

            const Text(
              "เลือกใช้ 1 สกิล?",
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w600,
                color: Colors.black,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),

            ...skills.map((skill) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: InkWell(
                onTap: () {
                  onSelect(skill);
                  Navigator.pop(context);
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFD9D9D9),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      Text(
                        skill.name,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        skill.description,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )),
          ],
        ),
      ),
    );
  }
}
