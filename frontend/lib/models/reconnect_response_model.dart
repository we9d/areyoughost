import 'package:areyoughost/models/game_phase_change_model.dart';
import 'package:areyoughost/models/role_model.dart';
import 'package:areyoughost/models/mock_models.dart';

/// ReconnectResponse (0x06) — Server response to reconnection attempt
/// 
/// Sent by the server when a client attempts to reconnect with a stored session_id.
/// If successful, contains the restored game state (phase, day number, role, alive status).
/// If unsuccessful, contains an error message.
class ReconnectResponse {
  final bool success;
  final String? roomId;
  final PhaseType? phase;
  final int? dayNumber;
  final int? phaseRemainingSecs;
  final bool? isAlive;
  final RoleInfo? role;
  final String? error;

  ReconnectResponse({
    required this.success,
    this.roomId,
    this.phase,
    this.dayNumber,
    this.phaseRemainingSecs,
    this.isAlive,
    this.role,
    this.error,
  });

  /// Deserialize from JSON (server sends JSON format for Dart compatibility)
  factory ReconnectResponse.fromJson(Map<String, dynamic> json) {
    return ReconnectResponse(
      success: json['success'] as bool? ?? false,
      roomId: json['room_id'] as String?,
      phase: json['phase'] != null
          ? PhaseType.values.firstWhere(
              (p) => p.name == json['phase'],
              orElse: () => PhaseType.day,
            )
          : null,
      dayNumber: json['day_number'] as int?,
      phaseRemainingSecs: json['phase_remaining_secs'] as int?,
      isAlive: json['is_alive'] as bool?,
      role: json['role'] != null
          ? RoleInfo.fromJson(json['role'] as Map<String, dynamic>)
          : null,
      error: json['error'] as String?,
    );
  }

  @override
  String toString() =>
      'ReconnectResponse(success: $success, roomId: $roomId, phase: $phase, '
      'dayNumber: $dayNumber, isAlive: $isAlive, error: $error)';
}
