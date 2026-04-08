import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:areyoughost/models/role_model.dart';

class GameDataService {
  static List<RoleData>? _cachedRoles;
  static List<SkillData>? _cachedSkills;

  static const List<int> magicBytes = [0xAE, 0x80];
  static const int getGameDataCode = 0x0F;

  static Future<void> fetchGameData() async {
    try {
      // Connect to the Rust TCP Server on Port 8888 (Binary Protocol)
      final socket = await Socket.connect('127.0.0.1', 8888, timeout: Duration(seconds: 5));
      print('Connected to Areyoughost TCP Server on 8888');

      // ── Build Frame [Magic(2), Type(1), Len(4), Payload(0), CRC(2)] ────────
      final header = ByteData(7);
      header.setUint8(0, magicBytes[0]);
      header.setUint8(1, magicBytes[1]);
      header.setUint8(2, getGameDataCode);
      header.setUint32(3, 0); // Length 0 for GetGameData Request

      // Calculate CRC (over Type + Length + Payload)
      // For Type(1) + Len(4) + EmptyPayload
      final checkData = Uint8List(5);
      checkData[0] = getGameDataCode;
      // Len 4 bytes (all 0)
      
      final crc = _calculateCrc16(checkData);
      final frame = Uint8List(9);
      frame.setAll(0, header.buffer.asUint8List());
      // Payload is empty
      frame[7] = (crc >> 8) & 0xFF; // CRC High
      frame[8] = crc & 0xFF;        // CRC Low

      socket.add(frame);
      await socket.flush();

      // ── Read Response ─────────
      final responseBytes = <int>[];
      int? expectedTotalLen;

      final subscription = socket.listen((data) {
        responseBytes.addAll(data);
        
        // Need at least 7 bytes for the header (Magic, Type, Length)
        if (expectedTotalLen == null && responseBytes.length >= 7) {
          final headerBytes = Uint8List.fromList(responseBytes.sublist(0, 7));
          final payloadLen = ByteData.sublistView(headerBytes, 3, 7).getUint32(0, Endian.big);
          expectedTotalLen = 7 + payloadLen + 2; // Header + Payload + CRC(2)
        }
      });

      // Simple implementation: wait for data or timeout
      int elapsed = 0;
      while (expectedTotalLen == null || responseBytes.length < expectedTotalLen!) {
        await Future.delayed(Duration(milliseconds: 50));
        elapsed += 50;
        if (elapsed > 5000) break; // 5s Timeout
        if (expectedTotalLen != null && responseBytes.length >= expectedTotalLen!) break;
      }
      await subscription.cancel();
      socket.destroy();

      if (expectedTotalLen == null || responseBytes.length < expectedTotalLen!) {
        print('Incomplete response from TCP server (Got ${responseBytes.length}, expected $expectedTotalLen)');
        return;
      }

      final headerBytes = Uint8List.fromList(responseBytes.sublist(0, 7));
      final payloadLen = ByteData.sublistView(headerBytes, 3, 7).getUint32(0, Endian.big);
      final payload = Uint8List.fromList(responseBytes.sublist(7, 7 + payloadLen));
      
      // Verification (Verify Magic & CRC in production)
      
      final data = jsonDecode(utf8.decode(payload));
      _cachedRoles = (data['roles'] as List)
          .map((json) => RoleData.fromJson(json))
          .toList();
      _cachedSkills = (data['skills'] as List)
          .map((json) => SkillData.fromJson(json))
          .toList();
      
      print('Successfully fetched ${_cachedRoles?.length} roles via binary protocol');
    } catch (e) {
      print('Error fetching game data via TCP: $e');
      // Fallback or retry logic...
    }
  }

  // CRC-16-IBM-SDLC (Kermit) matching the Rust server's implementation
  static int _calculateCrc16(Uint8List data) {
    int crc = 0xFFFF;
    for (int byte in data) {
      crc ^= byte;
      for (int i = 0; i < 8; i++) {
        if ((crc & 0x0001) != 0) {
          crc = (crc >> 1) ^ 0x8408; // Reflected 0x1021
        } else {
          crc >>= 1;
        }
      }
    }
    return (~crc) & 0xFFFF; // Final XOR
  }

  static List<RoleData> get roles => _cachedRoles ?? [];
  static List<SkillData> get skills => _cachedSkills ?? [];

  static RoleData? getRoleByCode(String code) {
    return _cachedRoles?.firstWhere(
      (r) => r.roleCode.toUpperCase() == code.toUpperCase(),
      orElse: () => _cachedRoles!.first, // Fallback
    );
  }
}
