import 'package:bootstrap_icons/bootstrap_icons.dart';
import 'package:areyoughost/ui/widgets/network_or_asset_image.dart';
import 'package:flutter/material.dart';

class RoleDropdownCard extends StatefulWidget {
  final String imagePath;
  final String roleName;
  final String team;
  final String aura;
  final String description;
  final bool initiallyExpanded;

  const RoleDropdownCard({
    super.key,
    required this.imagePath,
    required this.roleName,
    required this.team,
    required this.aura,
    required this.description,
    this.initiallyExpanded = false,
  });

  @override
  State<RoleDropdownCard> createState() => _RoleDropdownCardState();
}

class _RoleDropdownCardState extends State<RoleDropdownCard> {
  late bool _isExpanded;

  @override
  void initState() {
    super.initState();
    _isExpanded = widget.initiallyExpanded;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F3F3),
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(
            color: Color.fromARGB(60, 0, 0, 0),
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () {
              setState(() {
                _isExpanded = !_isExpanded;
              });
            },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              child: Row(
                children: [
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: NetworkOrAssetImage(
                        path: widget.imagePath,
                        fit: BoxFit.cover,
                        fallback: Image.asset(
                          'assets/images/V01.jpg',
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.roleName,
                          style: const TextStyle(
                            color: Colors.black,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'ฝ่าย : ${widget.team} , ออร่า : ${widget.aura}',
                          style: const TextStyle(
                            color: Colors.black87,
                            fontSize: 15,
                            height: 1.25,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    _isExpanded
                        ? BootstrapIcons.caret_up_fill
                        : BootstrapIcons.caret_down_fill,
                    color: Colors.black,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
          if (_isExpanded)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // const Divider(
                  //   color: Color(0xFFBDBDBD),
                  //   thickness: 1,
                  //   height: 10,
                  // ),
                  Text(
                    widget.description,
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 15,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}