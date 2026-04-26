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
}
