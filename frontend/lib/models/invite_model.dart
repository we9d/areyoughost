class Invite {
  final String inviteId;
  final String inviterName;
  final String roomId;
  final String inviteCode;

  Invite({
    required this.inviteId,
    required this.inviterName,
    required this.roomId,
    required this.inviteCode,
  });

  factory Invite.fromJson(Map<String, dynamic> json) {
    return Invite(
      inviteId: json['inviteId'] as String? ?? DateTime.now().millisecondsSinceEpoch.toString(),
      inviterName: json['fromUsername'] as String? ?? 'Unknown',
      roomId: json['roomId'] as String? ?? '',
      inviteCode: json['inviteCode'] as String? ?? '',
    );
  }
}
