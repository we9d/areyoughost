import 'dart:math';

import 'package:areyoughost/game/game_catalog.dart';

/// Role names that may appear in [buildBalancedRoleDeck] for [playerCount] (unordered set).
Set<String> balancedAllowedRoleNamesForCount(int playerCount) {
  final count = playerCount.clamp(2, 16);
  final evilCount = switch (count) {
    <= 4 => 1,
    <= 7 => 2,
    <= 10 => 3,
    <= 13 => 4,
    _ => 5,
  };
  final neutralCount = count >= 11 ? 2 : (count >= 6 ? 1 : 0);
  final goodCount = (count - evilCount - neutralCount).clamp(1, count);

  final allowed = <String>{};
  for (var i = 0; i < goodCount; i++) {
    allowed.add(GameRoles.balancedGoodCycle[i % GameRoles.balancedGoodCycle.length]);
  }
  for (var i = 0; i < evilCount; i++) {
    allowed.add(GameRoles.balancedEvilCycle[i % GameRoles.balancedEvilCycle.length]);
  }
  for (var i = 0; i < neutralCount; i++) {
    allowed.add(
      GameRoles.balancedNeutralCycle[i % GameRoles.balancedNeutralCycle.length],
    );
  }
  return allowed;
}

/// Balanced role multiset for local demo / quick play (matches RandomRoleScreen).
List<String> buildBalancedRoleDeck(int playerCount) {
  final count = playerCount.clamp(2, 16);
  final evilCount = switch (count) {
    <= 4 => 1,
    <= 7 => 2,
    <= 10 => 3,
    <= 13 => 4,
    _ => 5,
  };
  final neutralCount = count >= 11 ? 2 : (count >= 6 ? 1 : 0);
  final goodCount = (count - evilCount - neutralCount).clamp(1, count);

  final roles = <String>[
    for (var i = 0; i < goodCount; i++)
      GameRoles.balancedGoodCycle[i % GameRoles.balancedGoodCycle.length],
    for (var i = 0; i < evilCount; i++)
      GameRoles.balancedEvilCycle[i % GameRoles.balancedEvilCycle.length],
    for (var i = 0; i < neutralCount; i++)
      GameRoles.balancedNeutralCycle[i % GameRoles.balancedNeutralCycle.length],
  ];

  roles.shuffle(Random());
  return roles;
}
