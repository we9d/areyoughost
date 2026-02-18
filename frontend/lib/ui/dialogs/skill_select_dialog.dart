import 'package:flutter/material.dart';

class SkillOption {
  final String name;
  final String description;

  SkillOption({
    required this.name,
    required this.description,
  });
}

class SkillSelectDialog extends StatelessWidget {
  final List<SkillOption> skills;
  final ValueChanged<SkillOption> onSelect;

  const SkillSelectDialog({
    super.key,
    required this.skills,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'เลือกใช้ 1 สกิล?',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: skills.map((skill) {
                return GestureDetector(
                  onTap: () {
                    Navigator.pop(context);
                    onSelect(skill);
                  },
                  child: Container(
                    width: 120,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: [
                        const Icon(Icons.flash_on, size: 40),
                        const SizedBox(height: 8),
                        Text(
                          skill.name,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          skill.description,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}
