import 'package:flutter/material.dart';
import 'package:areyoughost/ui/widgets/icons/search_icon.dart';

class SearchFriend extends StatelessWidget {
  const SearchFriend({super.key});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [

          /// ช่องกรอกข้อความ
          Container(
            width: 210,
            height: 35,
            decoration: BoxDecoration(
              color: const Color(0xFFFFFFFF),
              borderRadius: BorderRadius.circular(60),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.35),
                  blurRadius: 12,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: const TextField(
              textAlign: TextAlign.start,
              style: TextStyle(
                color: Colors.black,
                fontSize: 16,
              ),
              decoration: InputDecoration(
                border: InputBorder.none,
                contentPadding: EdgeInsets.only(
                  left: 15,
                  right: 10,
                  bottom: 10,
                ),
              ),
            ),
          ),

          /// ระยะห่างระหว่างช่องกับไอคอน
          const SizedBox(width: 8),

          /// ไอคอนค้นหา
          const SearchIcon(
            size: 20,
            color: Colors.black,
          ),
        ],
      ),
    );
  }
}