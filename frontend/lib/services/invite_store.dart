import 'package:flutter/foundation.dart';

/// A pending invite received from a friend.
class PendingInvite {
  final String inviteCode;
  final String fromPlayerId;
  final String fromUsername;

  const PendingInvite({
    required this.inviteCode,
    required this.fromPlayerId,
    required this.fromUsername,
  });
}

/// Global store for pending game invites.
///
/// Listen to [invites] to rebuild UI when invites arrive/are dismissed.
class InviteStore {
  InviteStore._();
  static final InviteStore instance = InviteStore._();

  /// The list of pending invites — use a ValueNotifier so widgets can rebuild.
  final ValueNotifier<List<PendingInvite>> invites =
      ValueNotifier<List<PendingInvite>>([]);

  /// True if there is at least one pending invite.
  bool get hasInvite => invites.value.isNotEmpty;

  /// Add a new incoming invite.
  void add(PendingInvite invite) {
    // Avoid duplicates by inviteCode
    final current = List<PendingInvite>.from(invites.value);
    if (!current.any((i) => i.inviteCode == invite.inviteCode)) {
      current.add(invite);
      invites.value = current;
    }
  }

  /// Remove an invite by inviteCode (after accept or reject).
  void remove(String inviteCode) {
    invites.value = invites.value
        .where((i) => i.inviteCode != inviteCode)
        .toList();
  }

  /// Remove the first pending invite (convenience for single-invite case).
  void removeFirst() {
    if (invites.value.isNotEmpty) {
      invites.value = invites.value.sublist(1);
    }
  }
}
