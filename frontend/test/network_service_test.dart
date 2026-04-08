import 'dart:convert';
import 'dart:typed_data';

import 'package:areyoughost/models/game_event_model.dart';
import 'package:areyoughost/models/game_invite_received_model.dart';
import 'package:areyoughost/models/game_phase_change_model.dart';
import 'package:areyoughost/services/network_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });
  group('GameInviteReceived Model', () {
    test('GameInviteReceived model parses all fields correctly', () {
      // Arrange: Create a GameInviteReceived JSON
      final inviteJson = {
        'from_username': 'Alice',
        'room_id': 'room123',
        'room_name': 'Friendly Game',
      };

      // Act: Parse the JSON
      final invite = GameInviteReceived.fromJson(inviteJson);

      // Assert: Verify all fields
      expect(invite.fromUsername, 'Alice');
      expect(invite.roomId, 'room123');
      expect(invite.roomName, 'Friendly Game');
    });

    test('GameInviteReceived model handles missing fields with defaults', () {
      // Arrange: Create a minimal GameInviteReceived JSON
      final inviteJson = {
        'from_username': 'Bob',
      };

      // Act: Parse the JSON
      final invite = GameInviteReceived.fromJson(inviteJson);

      // Assert: Verify defaults for missing fields
      expect(invite.fromUsername, 'Bob');
      expect(invite.roomId, '');
      expect(invite.roomName, 'Unnamed Room');
    });

    test('GameInviteReceived model converts to JSON correctly', () {
      // Arrange: Create a GameInviteReceived instance
      final invite = GameInviteReceived(
        fromUsername: 'Charlie',
        roomId: 'room456',
        roomName: 'Epic Game',
      );

      // Act: Convert to JSON
      final json = invite.toJson();

      // Assert: Verify JSON structure
      expect(json['from_username'], 'Charlie');
      expect(json['room_id'], 'room456');
      expect(json['room_name'], 'Epic Game');
    });

    test('GameInviteReceived model toString works correctly', () {
      // Arrange: Create a GameInviteReceived instance
      final invite = GameInviteReceived(
        fromUsername: 'Diana',
        roomId: 'room789',
        roomName: 'Secret Game',
      );

      // Act: Convert to string
      final str = invite.toString();

      // Assert: Verify string representation
      expect(str, contains('Diana'));
      expect(str, contains('Secret Game'));
      expect(str, contains('room789'));
    });

    test('GameInviteReceived round-trip serialization', () {
      // Arrange: Create a GameInviteReceived instance
      final originalInvite = GameInviteReceived(
        fromUsername: 'Frank',
        roomId: 'room111',
        roomName: 'Round Trip Test',
      );

      // Act: Convert to JSON and back
      final json = originalInvite.toJson();
      final restoredInvite = GameInviteReceived.fromJson(json);

      // Assert: Verify round-trip integrity
      expect(restoredInvite.fromUsername, originalInvite.fromUsername);
      expect(restoredInvite.roomId, originalInvite.roomId);
      expect(restoredInvite.roomName, originalInvite.roomName);
    });
  });

  group('NetworkService - GameInviteReceived Integration', () {
    late NetworkService networkService;

    setUp(() {
      networkService = NetworkService();
    });

    tearDown(() {
      networkService.disconnect();
    });

    test('InviteEvent extends GameEvent correctly', () {
      // Arrange: Create a GameInviteReceived
      final invite = GameInviteReceived(
        fromUsername: 'Eve',
        roomId: 'room999',
        roomName: 'Test Game',
      );

      // Act: Create an InviteEvent
      final event = InviteEvent(invite: invite);

      // Assert: Verify inheritance and fields
      expect(event, isA<GameEvent>());
      expect(event.type.value, 0x1B); // gameInviteReceived opcode
      expect(event.invite, invite);
      expect(event.invite.fromUsername, 'Eve');
    });

    test('NetworkService stores pending invite correctly', () {
      // Arrange: Create a network service
      final service = NetworkService();

      // Act: Verify initial state
      expect(service.pendingInvite, isNull);

      // Note: We can't directly test _handleGameInviteReceived without mocking
      // the socket, but we can verify the getter works
    });

    test('NetworkService exposes events stream', () {
      // Arrange & Act: Get the events stream
      final eventsStream = networkService.events;

      // Assert: Verify it's a valid stream
      expect(eventsStream, isNotNull);
      expect(eventsStream, isA<Stream<GameEvent>>());
    });

    test('NetworkService disconnects cleanly', () async {
      // Arrange: Create a network service
      final service = NetworkService();

      // Act: Disconnect
      service.disconnect();

      // Assert: Verify disconnected state
      expect(service.isConnected, false);
    });
  });
}
