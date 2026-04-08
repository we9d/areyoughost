/// Areyoughost Binary Protocol — Message Type Opcodes
///
/// Each variant maps to a 1-byte opcode used in the frame header.
/// See design doc §2.3 Full Opcode Table.
enum MessageType {
  // Auth
  loginRequest(0x01),
  loginResponse(0x02),
  registerRequest(0x03),
  registerResponse(0x04),

  // Session recovery
  reconnectRequest(0x05),
  reconnectResponse(0x06),

  // Room management
  roomListRequest(0x10),
  roomListResponse(0x11),
  createRoomRequest(0x12),
  createRoomResponse(0x13),
  joinRoomRequest(0x14),
  joinRoomResponse(0x15),
  leaveRoomRequest(0x16),

  // Matchmaking
  quickJoinRequest(0x17),
  quickJoinResponse(0x18),
  startGame(0x19),

  // Invites
  invitePlayer(0x1A),
  gameInviteReceived(0x1B),

  // Room state
  roomStateSync(0x20),

  // In-game actions
  chatMessage(0x30),
  castVote(0x31),
  nightAction(0x32),
  gamePhaseChange(0x33),
  gameEvent(0x34),

  // Keep-alive
  heartbeat(0x50),

  // Disconnect
  disconnect(0x70),

  // Error
  error(0xFF),

  // Fallback
  unknown(0x00);

  const MessageType(this.value);

  /// The raw byte value of this opcode.
  final int value;

  /// Look up a [MessageType] by its byte value.
  /// Returns [MessageType.unknown] for unrecognized opcodes.
  static MessageType fromByte(int byte) {
    for (final type in MessageType.values) {
      if (type.value == byte) return type;
    }
    return MessageType.unknown;
  }
}
