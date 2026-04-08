// Mock models for development
// These will be replaced with actual FFI models later

class User {
  final String playerId;
  final String username;
  final String? email;

  User({
    required this.playerId,
    required this.username,
    this.email,
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
  final String roleCode;
  final String roleName;
  final String faction;
  final String description;

  Role({
    required this.roleId,
    required this.roleCode,
    required this.roleName,
    required this.faction,
    required this.description,
  });
}

class PlayerModel {
  final int number;
  final String name;
  final bool isAlive;

  PlayerModel({
    required this.number,
    required this.name,
    this.isAlive = true,
  });
}

class GameParticipant {
  final String playerId;
  final String username;
  final int seatNumber;
  final bool isAlive;
  final Role? role;

  GameParticipant({
    required this.playerId,
    required this.username,
    required this.seatNumber,
    required this.isAlive,
    this.role,
  });
}

class ChatMessage {
  final String messageId;
  final String senderId;
  final String messageText;
  final String chatScope;
  final DateTime createdAt;

  ChatMessage({
    required this.messageId,
    required this.senderId,
    required this.messageText,
    required this.chatScope,
    required this.createdAt,
  });
}

class RoleInfo {
  final String name;
  final String description;
  final int roleId;

  RoleInfo({required this.name, required this.description, this.roleId = 0});

  factory RoleInfo.fromJson(Map<String, dynamic> json) {
    return RoleInfo(
      name: (json['role_name'] ?? json['name'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      roleId: json['role_id'] ?? json['roleId'] ?? 0,
    );
  }
}

class SkillOption {
  final String name;
  final String description;
  final String image;
  final String skillId;

  SkillOption({
    required this.name,
    required this.description,
    required this.image,
    required this.skillId,
  });
}
