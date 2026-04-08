import 'package:areyoughost/src/rust/models.dart' as rust;

/// View model for the User, used for UI state and authentication.
class UserVM {
  final String playerId;
  final String username;
  final String? email;

  UserVM({
    required this.playerId,
    required this.username,
    this.email,
  });

  /// Factory constructor to create a UserVM from a generated Rust model.
  factory UserVM.fromRust(rust.User user) {
    return UserVM(
      playerId: user.playerId.toString(),
      username: user.username,
      email: user.email,
    );
  }

  @override
  String toString() => 'UserVM(playerId: $playerId, username: $username)';
}

/// View model for chat messages.
class ChatMessageVM {
  final String? senderId;
  final String content;
  final DateTime? timestamp;

  ChatMessageVM({
    this.senderId,
    required this.content,
    this.timestamp,
  });
}

/// Local Role enum for UI mapping, to avoid circular dependencies with generated code.
enum Role {
  ghost,
  serialKiller,
  spirit,
  villager,
  doctor,
  police,
  medium,
  warden,
  reaper,
  curser,
  specter,
}
