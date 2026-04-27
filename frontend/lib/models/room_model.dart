/// Room model from the server's room.state / room.joined event.
class RoomModel {
  final String roomId;
  final List<PlayerInfo> players;
  final int maxPlayers;
  final bool isPublic;
  final String status;
  final String? inviteCode;

  const RoomModel({
    required this.roomId,
    required this.players,
    required this.maxPlayers,
    required this.isPublic,
    required this.status,
    this.inviteCode,
  });

  factory RoomModel.fromJson(Map<String, dynamic> json) {
    return RoomModel(
      roomId: json['roomId'] as String? ?? '',
      players: (json['players'] as List<dynamic>? ?? [])
          .map((p) => PlayerInfo.fromJson(p as Map<String, dynamic>))
          .toList(),
      maxPlayers: (json['maxPlayers'] as num?)?.toInt() ?? 16,
      isPublic: (json['isPublic'] as bool?) ?? true,
      status: json['status'] as String? ?? 'waiting',
      inviteCode: json['inviteCode'] as String?,
    );
  }

  RoomModel copyWith({List<PlayerInfo>? players, String? status}) {
    return RoomModel(
      roomId: roomId,
      players: players ?? this.players,
      maxPlayers: maxPlayers,
      isPublic: isPublic,
      status: status ?? this.status,
      inviteCode: inviteCode,
    );
  }
}

class PlayerInfo {
  final String playerId;
  final String username;
  final bool isHost;
  final bool isReady;

  const PlayerInfo({
    required this.playerId,
    required this.username,
    required this.isHost,
    required this.isReady,
  });

  factory PlayerInfo.fromJson(Map<String, dynamic> json) {
    return PlayerInfo(
      playerId: json['playerId'] as String? ?? '',
      username: json['username'] as String? ?? 'Unknown',
      isHost: json['isHost'] as bool? ?? false,
      isReady: json['isReady'] as bool? ?? false,
    );
  }
}
