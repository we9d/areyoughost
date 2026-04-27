import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:areyoughost/models/mock_models.dart';
import 'package:areyoughost/services/app_config.dart';

/// Fetches joinable public rooms from the HTTP API (`GET /rooms/public`).
class LobbyService {
  LobbyService._();

  static Future<List<Room>> fetchPublicRooms() async {
    final uri = Uri.parse('${AppConfig.apiBaseUrl}/rooms/public');
    final response = await http.get(uri).timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) {
      throw Exception('rooms/public failed: ${response.statusCode}');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>?;
    if (data == null) {
      throw const FormatException('Invalid rooms response');
    }
    final arr = data['rooms'] as List<dynamic>? ?? [];
    return arr.map((raw) {
      final e = raw as Map<String, dynamic>;
      final maxP = (e['maxPlayers'] as num?)?.toInt() ?? 16;
      final curP = (e['currentPlayers'] as num?)?.toInt() ?? 0;
      return Room(
        roomId: e['roomId'] as String? ?? '',
        roomName: e['roomName'] as String? ?? 'ห้อง',
        maxPlayers: maxP,
        currentPlayers: curP,
        isPublic: (e['isPublic'] as bool?) ?? true,
        status: e['status'] as String? ?? 'waiting',
      );
    }).toList();
  }
}
