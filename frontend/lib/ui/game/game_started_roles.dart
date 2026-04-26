import 'package:areyoughost/services/auth_service.dart';

/// Parses `game.started` payload maps so UI matches server-assigned roles.

Map<String, String> parseRolesByPlayerIdFromPayload(dynamic raw) {
  final out = <String, String>{};
  if (raw is Map) {
    for (final entry in raw.entries) {
      final k = entry.key;
      final v = entry.value;
      if (k is String && v is String && k.trim().isNotEmpty && v.trim().isNotEmpty) {
        out[k] = v;
      }
    }
  }
  return out;
}

List<String> parseRolePoolFromPayload(dynamic raw) {
  if (raw is! List) return [];
  return raw
      .whereType<String>()
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();
}

/// Case-insensitive UUID / id match (server vs session string casing).
String? lookupRoleForPlayerId(Map<String, String> rolesById, String? playerId) {
  if (playerId == null || playerId.isEmpty) return null;
  final trimmed = playerId.trim();
  final direct = rolesById[trimmed];
  if (direct != null) return direct;
  final lower = trimmed.toLowerCase();
  for (final e in rolesById.entries) {
    if (e.key.trim().toLowerCase() == lower) return e.value;
  }
  return null;
}

String? assignedRoleForCurrentUser(Map<String, String> rolesById) {
  return lookupRoleForPlayerId(rolesById, AuthService.currentUser.value?.userId);
}
