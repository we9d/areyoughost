/// Represents a RoomStateSync (0x20) message from the server.
///
/// This message is broadcast to all players in a room when:
/// - A new player joins the room
/// - A player leaves the room
/// - A player's online status changes
///
/// The client uses this to update the local room model and notify the UI
/// (GameScreen) to refresh the player list display.
class RoomStateSync {
  final String roomId;
  final List<ParticipantInfo> participants;
  final int aliveCount;

  const RoomStateSync({
    required this.roomId,
    required this.participants,
    required this.aliveCount,
  });

  factory RoomStateSync.fromJson(Map<String, dynamic> json) {
    final participantsList = json['participants'] as List<dynamic>? ?? [];

    return RoomStateSync(
      roomId: json['room_id'] as String? ?? json['roomId'] as String? ?? '',
      participants: participantsList
          .map((p) => ParticipantInfo.fromJson(p as Map<String, dynamic>))
          .toList(),
      aliveCount: json['alive_count'] as int? ?? json['aliveCount'] as int? ?? 0,
    );
  }

  @override
  String toString() =>
      'RoomStateSync(roomId: $roomId, participants: ${participants.length}, alive: $aliveCount)';
}

/// Represents a participant in a room.
///
/// Fields:
/// - playerId: Unique identifier for the player
/// - username: Display name of the player
/// - isOnline: Whether the player is currently connected
/// - seatNumber: Position in the room (for UI layout), or -1 if not assigned
class ParticipantInfo {
  final String playerId;
  final String username;
  final bool isOnline;
  final int seatNumber;

  const ParticipantInfo({
    required this.playerId,
    required this.username,
    required this.isOnline,
    required this.seatNumber,
  });

  factory ParticipantInfo.fromJson(Map<String, dynamic> json) {
    return ParticipantInfo(
      playerId: json['player_id'] as String? ?? json['playerId'] as String? ?? '',
      username: json['username'] as String? ?? 'Unknown',
      isOnline: json['is_online'] as bool? ?? json['isOnline'] as bool? ?? true,
      seatNumber: json['seat_number'] as int? ?? json['seatNumber'] as int? ?? -1,
    );
  }

  @override
  String toString() =>
      'ParticipantInfo(playerId: $playerId, username: $username, online: $isOnline, seat: $seatNumber)';
}
