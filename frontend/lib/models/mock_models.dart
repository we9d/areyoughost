// Mock models for development
// These will be replaced with actual FFI models later

class User {
  final String userId;
  final String username;
  final String displayName;

  User({
    required this.userId,
    required this.username,
    required this.displayName,
  });
}

class Room {
  final String roomId;
  final String roomName;
  final int maxPlayers;
  final int currentPlayers;
  final bool isPublic;
  final String status;

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
  final String faction;
  final String description;

  Role({
    required this.roleId,
    required this.roleName,
    required this.faction,
    required this.description,
  });
}

class PlayerModel {
  final int number;
  final String name;

  PlayerModel({
    required this.number,
    required this.name,
  });
}

class GameParticipant {
  final String userId;
  final String username;
  final int seatNumber;
  final bool isAlive;
  final Role? role;

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
  final String phaseType;
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

class RoleInfo {
  final String name;
  final String description;

  RoleInfo({required this.name, required this.description});
}

class SkillOption {
  final String name;
  final String description;
  final String image;

  SkillOption({
    required this.name,
    required this.description,
    required this.image,
  });
}
