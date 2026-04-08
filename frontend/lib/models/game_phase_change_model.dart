import 'dart:typed_data';

/// Represents a phase type in the game.
enum PhaseType {
  night('Night'),
  day('Day'),
  vote('Vote');

  const PhaseType(this.displayName);
  final String displayName;

  /// Parse a phase type from a string (case-insensitive).
  static PhaseType fromString(String value) {
    return PhaseType.values.firstWhere(
      (phase) => phase.name.toLowerCase() == value.toLowerCase(),
      orElse: () => PhaseType.night,
    );
  }
}

/// Represents a chat entry in the night chat history.
class ChatEntry {
  final String senderId;
  final String senderUsername;
  final String message;
  final int timestamp;

  const ChatEntry({
    required this.senderId,
    required this.senderUsername,
    required this.message,
    required this.timestamp,
  });

  factory ChatEntry.fromJson(Map<String, dynamic> json) {
    return ChatEntry(
      senderId: json['sender_id'] as String? ?? json['senderId'] as String? ?? '',
      senderUsername: json['sender_username'] as String? ?? json['senderUsername'] as String? ?? '',
      message: json['message'] as String? ?? '',
      timestamp: json['timestamp'] as int? ?? 0,
    );
  }
}

/// Represents a GamePhaseChange (0x33) message from the server.
/// 
/// This message is broadcast to all players when a phase transition occurs.
/// The client uses this to:
/// 1. Update the displayed phase
/// 2. Start a local countdown timer from duration_secs
/// 3. Transition to WAITING_FOR_SERVER when timer hits 0 (if no new 0x33 arrives)
class GamePhaseChange {
  final PhaseType phase;
  final int dayNumber;
  final int durationSecs;
  final int serverTimestamp; // Unix epoch seconds
  final List<ChatEntry>? nightChatHistory;

  const GamePhaseChange({
    required this.phase,
    required this.dayNumber,
    required this.durationSecs,
    required this.serverTimestamp,
    this.nightChatHistory,
  });

  factory GamePhaseChange.fromJson(Map<String, dynamic> json) {
    final phaseStr = json['phase'] as String? ?? 'Night';
    final nightChatList = json['night_chat_history'] as List<dynamic>?;

    return GamePhaseChange(
      phase: PhaseType.fromString(phaseStr),
      dayNumber: json['day_number'] as int? ?? 1,
      durationSecs: json['duration_secs'] as int? ?? 60,
      serverTimestamp: json['server_timestamp'] as int? ?? 0,
      nightChatHistory: nightChatList
          ?.map((entry) => ChatEntry.fromJson(entry as Map<String, dynamic>))
          .toList(),
    );
  }

  @override
  String toString() =>
      'GamePhaseChange(phase: ${phase.displayName}, day: $dayNumber, duration: ${durationSecs}s, timestamp: $serverTimestamp)';
}
