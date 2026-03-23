class InviteModel {
  final String inviteCode;
  final String fromPlayerId;
  final String fromUsername;
  final DateTime receivedAt;

  InviteModel({
    required this.inviteCode,
    required this.fromPlayerId,
    required this.fromUsername,
    required this.receivedAt,
  });

  factory InviteModel.fromJson(Map<String, dynamic> json) {
    return InviteModel(
      inviteCode: json['inviteCode'] as String? ?? '',
      fromPlayerId: json['fromPlayerId'] as String? ?? 'unknown',
      fromUsername: json['fromUsername'] as String? ?? 'Unknown Host',
      // We assign the receive time locally if the server doesn't provide it
      receivedAt: DateTime.now(),
    );
  }
}
