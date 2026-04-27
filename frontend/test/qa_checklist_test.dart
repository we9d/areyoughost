import 'package:areyoughost/game/game_catalog.dart';
import 'package:areyoughost/ui/game/role_deck.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('QA: Flutter asset manifest is present (json or bin)', () async {
    try {
      final raw = await rootBundle.loadString('AssetManifest.json');
      expect(raw.isNotEmpty, true);
    } catch (_) {
      final bin = await rootBundle.load('AssetManifest.bin');
      expect(bin.lengthInBytes, greaterThan(0));
    }
  });

  test('QA: balanced deck uses catalog cycles', () {
    final deck = buildBalancedRoleDeck(8);
    expect(deck.length, 8);
    for (final r in deck) {
      expect(
        GameRoles.balancedGoodCycle.contains(r) ||
            GameRoles.balancedEvilCycle.contains(r) ||
            GameRoles.balancedNeutralCycle.contains(r),
        true,
        reason: 'unexpected role $r',
      );
    }
  });

  test('QA: allowed role set matches deck composition for count', () {
    const n = 10;
    final allowed = balancedAllowedRoleNamesForCount(n);
    final deck = buildBalancedRoleDeck(n);
    expect(allowed.length, deck.toSet().length);
    for (final r in deck) {
      expect(allowed.contains(r), true);
    }
  });

  test('QA: balanced deck clamps player count to 2..16', () {
    expect(buildBalancedRoleDeck(1).length, 2);
    expect(buildBalancedRoleDeck(2).length, 2);
    expect(buildBalancedRoleDeck(16).length, 16);
    expect(buildBalancedRoleDeck(30).length, 16);
  });

  test('QA: balanced deck category quotas are correct', () {
    int expectedEvil(int count) => switch (count) {
      <= 4 => 1,
      <= 7 => 2,
      <= 10 => 3,
      <= 13 => 4,
      _ => 5,
    };

    int expectedNeutral(int count) => count >= 11 ? 2 : (count >= 6 ? 1 : 0);

    for (var n = 2; n <= 16; n++) {
      final deck = buildBalancedRoleDeck(n);
      final evil = deck
          .where((r) => GameRoles.balancedEvilCycle.contains(r))
          .length;
      final neutral = deck
          .where((r) => GameRoles.balancedNeutralCycle.contains(r))
          .length;
      final good = deck
          .where((r) => GameRoles.balancedGoodCycle.contains(r))
          .length;

      expect(evil, expectedEvil(n), reason: 'evil quota mismatch at n=$n');
      expect(
        neutral,
        expectedNeutral(n),
        reason: 'neutral quota mismatch at n=$n',
      );
      expect(good + evil + neutral, n, reason: 'deck size mismatch at n=$n');
    }
  });
}
