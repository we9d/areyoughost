import 'dart:convert';

import 'package:areyoughost/services/app_config.dart';
import 'package:http/http.dart' as http;

class IncomingFriendRequest {
  final String friendshipId;
  final String playerId;
  final String username;

  const IncomingFriendRequest({
    required this.friendshipId,
    required this.playerId,
    required this.username,
  });

  factory IncomingFriendRequest.fromJson(Map<String, dynamic> json) {
    return IncomingFriendRequest(
      friendshipId: json['friendship_id'] as String? ?? '',
      playerId: json['player_id'] as String? ?? '',
      username: json['username'] as String? ?? 'Unknown',
    );
  }
}

class FriendItem {
  final String playerId;
  final String username;
  final bool isOnline;

  const FriendItem({
    required this.playerId,
    required this.username,
    required this.isOnline,
  });

  factory FriendItem.fromJson(Map<String, dynamic> json) {
    return FriendItem(
      playerId: json['player_id'] as String? ?? '',
      username: json['username'] as String? ?? 'Unknown',
      isOnline: json['is_online'] as bool? ?? false,
    );
  }
}

class OutgoingFriendRequest {
  final String playerId;
  final String username;

  const OutgoingFriendRequest({
    required this.playerId,
    required this.username,
  });

  factory OutgoingFriendRequest.fromJson(Map<String, dynamic> json) {
    return OutgoingFriendRequest(
      playerId: json['player_id'] as String? ?? '',
      username: json['username'] as String? ?? 'Unknown',
    );
  }
}

class FriendsOverview {
  final List<IncomingFriendRequest> incomingRequests;
  final List<FriendItem> friends;
  final List<OutgoingFriendRequest> outgoingRequests;

  const FriendsOverview({
    required this.incomingRequests,
    required this.friends,
    required this.outgoingRequests,
  });

  factory FriendsOverview.fromJson(Map<String, dynamic> json) {
    return FriendsOverview(
      incomingRequests: (json['incoming_requests'] as List<dynamic>? ?? <dynamic>[])
          .map((e) => IncomingFriendRequest.fromJson(e as Map<String, dynamic>))
          .toList(growable: false),
      friends: (json['friends'] as List<dynamic>? ?? <dynamic>[])
          .map((e) => FriendItem.fromJson(e as Map<String, dynamic>))
          .toList(growable: false),
      outgoingRequests: (json['outgoing_requests'] as List<dynamic>? ?? <dynamic>[])
          .map((e) => OutgoingFriendRequest.fromJson(e as Map<String, dynamic>))
          .toList(growable: false),
    );
  }
}

class FriendService {
  static Future<FriendsOverview> getOverview(String userId) async {
    final uri = Uri.parse('${AppConfig.apiBaseUrl}/friends/overview').replace(
      queryParameters: <String, String>{'user_id': userId},
    );
    final response = await http.get(uri, headers: {'Content-Type': 'application/json'});
    if (response.statusCode != 200) {
      throw Exception('โหลดข้อมูลเพื่อนไม่สำเร็จ (HTTP ${response.statusCode})');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return FriendsOverview.fromJson(data);
  }

  static Future<void> sendRequest({
    required String fromUserId,
    required String toUserId,
  }) async {
    final response = await http.post(
      Uri.parse('${AppConfig.apiBaseUrl}/friends/request'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'from_user_id': fromUserId,
        'to_user_id': toUserId,
      }),
    );
    if (response.statusCode == 200) return;
    throw Exception(_errorFromResponse(response, fallback: 'ส่งคำขอเป็นเพื่อนไม่สำเร็จ'));
  }

  static Future<void> respondRequest({
    required String friendshipId,
    required String userId,
    required bool accept,
  }) async {
    final response = await http.post(
      Uri.parse('${AppConfig.apiBaseUrl}/friends/respond'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'friendship_id': friendshipId,
        'user_id': userId,
        'action': accept ? 'ACCEPT' : 'REJECT',
      }),
    );
    if (response.statusCode == 200) return;
    throw Exception(_errorFromResponse(response, fallback: 'ตอบรับคำขอไม่สำเร็จ'));
  }

  static String _errorFromResponse(http.Response response, {required String fallback}) {
    if (response.body.isNotEmpty) {
      try {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final error = json['error'];
        if (error is String && error.isNotEmpty) return error;
      } catch (_) {}
    }
    return '$fallback (HTTP ${response.statusCode})';
  }
}
