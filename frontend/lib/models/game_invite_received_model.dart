/// GameInviteReceived model — represents an incoming game invite from another player.
/// 
/// Payload structure (from design doc §2.4):
/// - from_username: String (who sent the invite)
/// - room_id: String (which room to join)
/// - room_name: String (display name of the room)
class GameInviteReceived {
  final String fromUsername;
  final String roomId;
  final String roomName;

  GameInviteReceived({
    required this.fromUsername,
    required this.roomId,
    required this.roomName,
  });

  factory GameInviteReceived.fromJson(Map<String, dynamic> json) {
    return GameInviteReceived(
      fromUsername: json['from_username'] as String? ?? 'Unknown',
      roomId: json['room_id'] as String? ?? '',
      roomName: json['room_name'] as String? ?? 'Unnamed Room',
    );
  }

  Map<String, dynamic> toJson() => {
    'from_username': fromUsername,
    'room_id': roomId,
    'room_name': roomName,
  };

  @override
  String toString() =>
      'GameInviteReceived(from: $fromUsername, room: $roomName, roomId: $roomId)';
}
