/// Represents the type of game event.
enum GameEventType {
  nightResolution('NightResolution'),
  voteResult('VoteResult'),
  gameOver('GameOver'),
  avengerVengeance('AvengerVengeance'),
  nemesisWin('NemesisWin'),
  foolWin('FoolWin');

  const GameEventType(this.displayName);
  final String displayName;

  /// Parse a game event type from a string (case-insensitive).
  static GameEventType fromString(String value) {
    return GameEventType.values.firstWhere(
      (type) => type.name.toLowerCase() == value.toLowerCase(),
      orElse: () => GameEventType.nightResolution,
    );
  }
}

/// Represents information about a player death.
class DeathInfo {
  final String playerId;
  final String username;
  final String roleName;

  const DeathInfo({
    required this.playerId,
    required this.username,
    required this.roleName,
  });

  factory DeathInfo.fromJson(Map<String, dynamic> json) {
    return DeathInfo(
      playerId: json['player_id'] as String? ?? json['playerId'] as String? ?? '',
      username: json['username'] as String? ?? '',
      roleName: json['role_name'] as String? ?? json['roleName'] as String? ?? '',
    );
  }

  @override
  String toString() => 'DeathInfo(player: $username, role: $roleName)';
}

/// Represents a GameEvent (0x34) message from the server.
/// 
/// This message is broadcast to all players when:
/// - Night phase ends (NightResolution event with deaths)
/// - Vote phase ends (VoteResult event with eliminated player)
/// - Game ends (GameOver event with winner_faction)
/// - Special events occur (AvengerVengeance, NemesisWin, FoolWin)
/// 
/// The client uses this to:
/// 1. Display death notifications
/// 2. Reveal roles of eliminated players
/// 3. Show game-over screens with winner announcement
/// 4. Handle special event triggers
class GameEventModel {
  final GameEventType eventType;
  final List<DeathInfo> deaths;
  final String? winnerFaction; // 'Villager', 'Ghost', 'SerialKiller', 'Draw', 'Nemesis'
  final Map<String, dynamic>? extra; // Additional data for special events

  const GameEventModel({
    required this.eventType,
    required this.deaths,
    this.winnerFaction,
    this.extra,
  });

  factory GameEventModel.fromJson(Map<String, dynamic> json) {
    final eventTypeStr = json['event_type'] as String? ?? 'NightResolution';
    final deathsList = json['deaths'] as List<dynamic>?;
    final extraData = json['extra'] as Map<String, dynamic>?;

    return GameEventModel(
      eventType: GameEventType.fromString(eventTypeStr),
      deaths: deathsList
          ?.map((death) => DeathInfo.fromJson(death as Map<String, dynamic>))
          .toList() ?? [],
      winnerFaction: json['winner_faction'] as String?,
      extra: extraData,
    );
  }

  @override
  String toString() =>
      'GameEventModel(type: ${eventType.displayName}, deaths: ${deaths.length}, winner: $winnerFaction)';
}
