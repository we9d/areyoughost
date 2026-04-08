class RoomModel {
  final String roomId;
  final List<PlayerInfo> players;
  final int maxPlayers;
  final String roomType; // 'PUBLIC' or 'PRIVATE'
  final String status;   // 'WAITING', 'STARTING', 'PLAYING', 'FINISHED', 'CLOSED'
  final String ownerId;
  final String? autoStartAt; // ISO8601 timestamp
  final String? currentPhase; // 'Day', 'Vote', 'Night'
  final int? phaseEndTime;   // Unix timestamp

  const RoomModel({
    required this.roomId,
    required this.players,
    required this.maxPlayers,
    required this.roomType,
    required this.status,
    required this.ownerId,
    this.autoStartAt,
    this.currentPhase,
    this.phaseEndTime,
  });

  factory RoomModel.fromJson(Map<String, dynamic> json) {
    return RoomModel(
      roomId: (json['room_id'] ?? json['roomId'] ?? '').toString(),
      players: (json['players'] as List<dynamic>? ?? [])
          .map((p) => PlayerInfo.fromJson(p as Map<String, dynamic>))
          .toList(),
      maxPlayers: json['max_players'] ?? json['maxPlayers'] ?? 16,
      roomType: (json['room_type'] ?? json['roomType'] ?? 'PUBLIC').toString(),
      status: (json['room_status'] ?? json['status'] ?? 'WAITING').toString(),
      ownerId: (json['owner_id'] ?? json['ownerId'] ?? '').toString(),
      autoStartAt: (json['auto_start_at'] ?? json['autoStartAt'])?.toString(),
      currentPhase: (json['current_phase'] ?? json['currentPhase'])?.toString(),
      phaseEndTime: json['phase_end_time'] ?? json['phaseEndTime'],
    );
  }

  bool get isQuickPlay => roomType == 'QUICK' || roomType == 'PUBLIC';
  bool get isPrivate => roomType == 'PRIVATE';
  bool get isLobby => status == 'WAITING' || status == 'STARTING';

  RoomModel copyWith({
    List<PlayerInfo>? players, 
    String? status,
    String? currentPhase,
    int? phaseEndTime,
  }) {
    return RoomModel(
      roomId: roomId,
      players: players ?? this.players,
      maxPlayers: maxPlayers,
      roomType: roomType,
      status: status ?? this.status,
      ownerId: ownerId,
      autoStartAt: autoStartAt,
      currentPhase: currentPhase ?? this.currentPhase,
      phaseEndTime: phaseEndTime ?? this.phaseEndTime,
    );
  }
}

class PlayerInfo {
  final String playerId;
  final String username;
  final bool isHost;
  final bool isOnline;
  final int seatNumber;

  const PlayerInfo({
    required this.playerId,
    required this.username,
    required this.isHost,
    this.isOnline = true,
    this.seatNumber = -1,
  });

  factory PlayerInfo.fromJson(Map<String, dynamic> json) {
    return PlayerInfo(
      playerId: (json['player_id'] ?? json['playerId'] ?? '').toString(),
      username: (json['username'] as String?) ?? 'Unknown',
      isHost: json['is_host'] ?? json['isHost'] ?? false,
      isOnline: json['is_online'] ?? json['isOnline'] ?? true,
      seatNumber: json['seat_number'] ?? json['seatNumber'] ?? -1,
    );
  }
}
