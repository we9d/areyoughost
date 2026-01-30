
// Mocking the Rust/FFI generated models for now

class User {
  final String userId;
  final String username;
  final String displayName;

  User({required this.userId, required this.username, required this.displayName});
}

class Room {
  final String roomId;
  final String roomName;
  final int maxPlayers;
  final int currentPlayers;
  final bool isPublic;
  final String status; // 'waiting', 'playing'

  Room({
    required this.roomId,
    required this.roomName,
    required this.maxPlayers,
    required this.currentPlayers,
    required this.isPublic,
    required this.status,
  });
}

class Role {
  final int roleId;
  final String roleName;
  final String faction; // 'villager', 'wolf', 'neutral'
  final String description;

  Role({required this.roleId, required this.roleName, required this.faction, required this.description});
}

class GameParticipant {
  final String userId;
  final String username; // Added for convenience in UI
  final int seatNumber;
  final bool isAlive;
  final Role? role; // Visible only if self or revealed

  GameParticipant({
    required this.userId,
    required this.username,
    required this.seatNumber,
    required this.isAlive,
    this.role,
  });
}

class ChatMessage {
  final String messageId;
  final String senderId;
  final String senderName;
  final String message;
  final String phaseType; // 'day', 'night', 'vote'
  final DateTime createdAt;

  ChatMessage({
    required this.messageId,
    required this.senderId,
    required this.senderName,
    required this.message,
    required this.phaseType,
    required this.createdAt,
  });
}
