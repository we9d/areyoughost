import 'package:flutter/material.dart';

class RoleInfo {
  final String name;
  final String description;

  RoleInfo({
    required this.name,
    required this.description,
  });
}

class RoleInfoDialog extends StatelessWidget {
  final List<RoleInfo> roles;

  const RoleInfoDialog({
    super.key,
    required this.roles,
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
              'บทบาท',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: roles.map((role) {
                  return ExpansionTile(
                    title: Text(role.name),
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(role.description),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
