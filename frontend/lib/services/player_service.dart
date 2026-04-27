import 'dart:convert';

import 'package:areyoughost/services/app_config.dart';
import 'package:http/http.dart' as http;

class PlayerLookupItem {
  final String playerId;
  final String username;

  const PlayerLookupItem({
    required this.playerId,
    required this.username,
  });

  factory PlayerLookupItem.fromJson(Map<String, dynamic> json) {
    return PlayerLookupItem(
      playerId: json['player_id'] as String? ?? '',
      username: json['username'] as String? ?? 'Unknown',
    );
  }
}

class PlayerService {
  static Future<List<PlayerLookupItem>> searchPlayers({
    required String query,
    String? excludeUserId,
  }) async {
    final q = query.trim();
    if (q.length < 2) return const <PlayerLookupItem>[];

    final uri = Uri.parse('${AppConfig.apiBaseUrl}/players/search').replace(
      queryParameters: <String, String>{
        'q': q,
        if (excludeUserId != null && excludeUserId.isNotEmpty) 'exclude': excludeUserId,
      },
    );

    final response = await http.get(uri, headers: {'Content-Type': 'application/json'});
    if (response.statusCode != 200) {
      throw Exception('ค้นหาผู้เล่นไม่สำเร็จ (HTTP ${response.statusCode})');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final rows = (data['players'] as List<dynamic>? ?? <dynamic>[]);
    return rows
        .map((r) => PlayerLookupItem.fromJson(r as Map<String, dynamic>))
        .toList(growable: false);
  }
}
