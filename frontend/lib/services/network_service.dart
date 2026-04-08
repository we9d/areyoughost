import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:areyoughost/models/game_event_model.dart';
import 'package:areyoughost/models/game_invite_received_model.dart';
import 'package:areyoughost/models/game_phase_change_model.dart';
import 'package:areyoughost/models/reconnect_response_model.dart';
import 'package:areyoughost/models/room_state_sync_model.dart';
import 'package:areyoughost/services/message_type.dart';
import 'package:areyoughost/services/session_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ---------------------------------------------------------------------------
// GameEvent — typed event pushed to the StreamController
// ---------------------------------------------------------------------------

class GameEvent {
  final MessageType type;
  final Uint8List payload;

  const GameEvent({required this.type, required this.payload});

  @override
  String toString() => 'GameEvent(type: $type, payloadLength: ${payload.length})';
}

// ---------------------------------------------------------------------------
// PhaseChangeEvent — specialized event for phase transitions
// ---------------------------------------------------------------------------

class PhaseChangeEvent extends GameEvent {
  final GamePhaseChange phaseChange;

  PhaseChangeEvent({required this.phaseChange})
      : super(type: MessageType.gamePhaseChange, payload: Uint8List(0));

  @override
  String toString() => 'PhaseChangeEvent($phaseChange)';
}

// ---------------------------------------------------------------------------
// RoomSyncEvent — specialized event for room state updates
// ---------------------------------------------------------------------------

class RoomSyncEvent extends GameEvent {
  final RoomStateSync roomSync;

  RoomSyncEvent({required this.roomSync})
      : super(type: MessageType.roomStateSync, payload: Uint8List(0));

  @override
  String toString() => 'RoomSyncEvent($roomSync)';
}

// ---------------------------------------------------------------------------
// InviteEvent — specialized event for game invites
// ---------------------------------------------------------------------------

class InviteEvent extends GameEvent {
  final GameInviteReceived invite;

  InviteEvent({required this.invite})
      : super(type: MessageType.gameInviteReceived, payload: Uint8List(0));

  @override
  String toString() => 'InviteEvent($invite)';
}

// ---------------------------------------------------------------------------
// NetworkService — singleton TCP client with background listener loop
// ---------------------------------------------------------------------------

class NetworkService {
  static final NetworkService _instance = NetworkService._internal();
  factory NetworkService() => _instance;
  NetworkService._internal();

  Socket? _socket;
  String? _host;
  int? _port;

  StreamController<GameEvent> _eventController =
      StreamController<GameEvent>.broadcast();

  /// Reactive stream of parsed game events for the UI to subscribe to.
  Stream<GameEvent> get events => _eventController.stream;

  /// Get the current pending invite (if any).
  GameInviteReceived? get pendingInvite => _pendingInvite;

  bool isConnected = false;

  /// Timer for the current phase countdown. Cancelled when a new phase arrives.
  Timer? _phaseCountdownTimer;

  /// Current phase state for UI synchronization.
  GamePhaseChange? _currentPhase;

  /// Pending game invite — new invite overwrites previous one.
  GameInviteReceived? _pendingInvite;

  /// Stored session_id from successful login (for reconnection)
  String? _sessionId;

  /// Reconnect retry state
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 5;
  static const Duration _reconnectBaseDelay = Duration(seconds: 2);

  // -------------------------------------------------------------------------
  // connect
  // -------------------------------------------------------------------------

  /// Opens a TCP connection to [host]:[port] and starts the listener loop.
  Future<void> connect(String host, int port) async {
    if (isConnected) return;

    // Store host and port for potential reconnection
    _host = host;
    _port = port;

    // Re-create the controller if it was previously closed.
    if (_eventController.isClosed) {
      _eventController = StreamController<GameEvent>.broadcast();
    }

    try {
      debugPrint('🔌 Connecting to $host:$port …');
      _socket = await Socket.connect(host, port);
      isConnected = true;
      _reconnectAttempts = 0; // Reset reconnect counter on successful connection
      debugPrint('✅ Connected to $host:$port');
      _startListenerLoop();

      // Trigger the session handshake immediately to identify ourselves to the server
      _sendReconnectRequest();
    } catch (e) {
      isConnected = false;
      debugPrint('❌ Connection failed: $e');
      rethrow;
    }
  }

  // -------------------------------------------------------------------------
  // sendMessage
  // -------------------------------------------------------------------------

  /// Writes a pre-serialised Areyoughost frame to the socket.
  Future<void> sendMessage(Uint8List frameBytes) async {
    final socket = _socket;
    if (socket == null || !isConnected) {
      throw StateError('NetworkService: not connected');
    }
    socket.add(frameBytes);
    await socket.flush();
  }

  /// Sends a 0x17 QuickJoinRequest to the server.
  Future<void> sendQuickJoinRequest() async {
    // Requirements: include player_id (UUID string)
    final userId = await SessionManager.getUserId();
    if (userId == null) {
      throw StateError('NetworkService: Cannot quick join without a logged-in session');
    }

    final payload = jsonEncode({
      'player_id': userId,
    });
    final payloadBytes = utf8.encode(payload);
    final frame = _buildFrame(MessageType.quickJoinRequest.value, payloadBytes);
    await sendMessage(frame);
  }

  // -------------------------------------------------------------------------
  // _startListenerLoop  (background async loop — Requirement 6.1)
  // -------------------------------------------------------------------------

  /// Continuously reads bytes from [_socket], accumulates them in a buffer,
  /// and slices complete Areyoughost frames for [_parseFrame].
  ///
  /// Frame layout:
  ///   [0xAE][0x80][Type 1B][PayloadLen 4B BE][Payload NB][CRC16 2B]
  ///   Minimum frame size = 9 bytes (empty payload).
  void _startListenerLoop() {
    final socket = _socket;
    if (socket == null) return;

    // Accumulation buffer — grows as bytes arrive.
    final List<int> _buffer = [];
    socket.listen(
      (Uint8List incoming) {
        // Append incoming bytes to the buffer
        _buffer.addAll(incoming);

        // Loop แกะกล่องแพ็กเก็ตตราบใดที่ข้อมูลใน Buffer ยังยาวพอสำหรับ Header (8 ไบต์)
        while (_buffer.length >= 8) {
          // 1. เช็ก Magic Bytes
          if (_buffer[0] != 0xAE || _buffer[1] != 0x80) {
            debugPrint("🚨 Invalid Magic Bytes! Clearing buffer.");
            _buffer.clear();
            return;
          }

          // 2. อ่าน Payload Length (4 Bytes แบบ Big-Endian) อยู่ที่ตำแหน่ง 4-7
          var byteData = ByteData.sublistView(Uint8List.fromList(_buffer), 4, 8);
          int payloadLen = byteData.getUint32(0, Endian.big);
          int totalPacketLen = 8 + payloadLen + 2; // Header(8) + Payload + CRC(2)

          // 3. เช็กว่า Byte มาครบทั้งแพ็กเก็ตหรือยัง? ถ้ายังให้รอรอบหน้า
          if (_buffer.length < totalPacketLen) {
            break; // รอ TCP ส่งข้อมูลส่วนที่เหลือตามมา
          }

          // 4. ข้อมูลมาครบแล้ว! ตัดแบ่งแพ็กเก็ตออกมาให้สมบูรณ์ (รวม header/crc)
          final frameBytes = Uint8List.fromList(_buffer.sublist(0, totalPacketLen));
          _parseFrame(frameBytes);

          // 6. ลบแพ็กเก็ตนี้ออกจาก Buffer
          _buffer.removeRange(0, totalPacketLen);
        }
      },
      onError: (Object error, StackTrace stack) {
        debugPrint('❌ Socket error: $error');
        _handleDisconnect();
      },
      onDone: () {
        debugPrint('🔌 Socket EOF — server closed connection');
        _handleDisconnect();
      },
      cancelOnError: true,
    );
  }

  /// Handles disconnection and cleanup.
  void _handleDisconnect() {
    isConnected = false;
    _socket?.destroy();
    _socket = null;

    // Cancel any pending phase countdown timer
    _phaseCountdownTimer?.cancel();
    _phaseCountdownTimer = null;

    if (!_eventController.isClosed) {
      // Push a sentinel disconnect event so the UI can react.
      _eventController.add(
        GameEvent(type: MessageType.disconnect, payload: Uint8List(0)),
      );
    }

    // Attempt to reconnect if we have a stored session_id and haven't exceeded max attempts
    if (_sessionId != null && _reconnectAttempts < _maxReconnectAttempts) {
      _attemptReconnect();
    } else {
      // No session or max attempts exceeded: close the controller
      if (!_eventController.isClosed) {
        _eventController.close();
      }
    }
  }

  /// Attempts to reconnect to the server using the stored session_id.
  /// Uses exponential backoff for retry delays.
  Future<void> _attemptReconnect() async {
    _reconnectAttempts++;
    
    // Calculate exponential backoff delay: 2s, 4s, 8s, 16s, 32s
    final delaySeconds = _reconnectBaseDelay.inSeconds * (1 << (_reconnectAttempts - 1));
    final delay = Duration(seconds: delaySeconds);

    debugPrint(
      '🔄 Reconnect attempt $_reconnectAttempts/$_maxReconnectAttempts '
      'in ${delay.inSeconds}s (session_id: ${_sessionId?.substring(0, 8)}...)',
    );

    // Wait before attempting reconnect
    await Future.delayed(delay);

    if (_sessionId == null || _host == null || _port == null) {
      debugPrint('❌ Cannot reconnect: missing session_id, host, or port');
      if (!_eventController.isClosed) {
        _eventController.close();
      }
      return;
    }

    try {
      debugPrint('🔌 Attempting to reconnect to $_host:$_port …');
      _socket = await Socket.connect(_host!, _port!);
      isConnected = true;
      _reconnectAttempts = 0; // Reset counter on successful connection
      debugPrint('✅ Reconnected to $_host:$_port');

      // Re-create the event controller if it was closed
      if (_eventController.isClosed) {
        _eventController = StreamController<GameEvent>.broadcast();
      }

      // Start the listener loop again
      _startListenerLoop();

      // Send ReconnectRequest (0x05) with stored session_id
      await _sendReconnectRequest();
    } catch (e) {
      debugPrint('❌ Reconnect attempt $_reconnectAttempts failed: $e');
      isConnected = false;
      _socket?.destroy();
      _socket = null;

      // Retry if we haven't exceeded max attempts
      if (_reconnectAttempts < _maxReconnectAttempts) {
        _attemptReconnect();
      } else {
        debugPrint('❌ Max reconnect attempts exceeded. Giving up.');
        if (!_eventController.isClosed) {
          _eventController.close();
        }
      }
    }
  }

  /// Sends a ReconnectRequest (0x05) with the stored session_id.
  Future<void> _sendReconnectRequest() async {
    if (_sessionId == null) {
      debugPrint('❌ Cannot send ReconnectRequest: no session_id stored');
      return;
    }

    try {
      // Build ReconnectRequest payload: { "session_id": "..." }
      final payload = jsonEncode({'session_id': _sessionId});
      final payloadBytes = utf8.encode(payload);

      // Build Areyoughost frame
      final frame = _buildFrame(0x05, payloadBytes);

      debugPrint('📤 Sending ReconnectRequest (0x05) with session_id');
      await sendMessage(frame);
    } catch (e) {
      debugPrint('❌ Error sending ReconnectRequest: $e');
    }
  }

  /// Builds an Areyoughost frame with the given opcode and payload bytes.
  /// Frame layout: [Magic 2B][Version 1B][Type 1B][PayloadLen 4B BE][Payload NB][CRC16 2B]
  Uint8List _buildFrame(int opcode, Uint8List payload) {
    const version = 1;
    final payloadLength = payload.length;
    final frame = Uint8List(10 + payloadLength);

    // Magic bytes
    frame[0] = 0xAE;
    frame[1] = 0x80;

    // Version byte
    frame[2] = version;

    // Type byte
    frame[3] = opcode;

    // Payload length (4B big-endian) at 4-7
    frame[4] = (payloadLength >> 24) & 0xFF;
    frame[5] = (payloadLength >> 16) & 0xFF;
    frame[6] = (payloadLength >> 8) & 0xFF;
    frame[7] = payloadLength & 0xFF;

    // Payload starts at 8
    frame.setAll(8, payload);

    // CRC16-IBM-SDLC over [version][type][length(4B)][payload]
    final crcInput = Uint8List(1 + 1 + 4 + payloadLength);
    crcInput[0] = version;
    crcInput[1] = opcode;
    crcInput[2] = frame[4];
    crcInput[3] = frame[5];
    crcInput[4] = frame[6];
    crcInput[5] = frame[7];
    crcInput.setAll(6, payload);

    final crc = _crc16IbmSdlc(crcInput);

    // CRC16 (2B big-endian) at the end
    frame[8 + payloadLength] = (crc >> 8) & 0xFF;
    frame[9 + payloadLength] = crc & 0xFF;

    return frame;
  }

  // -------------------------------------------------------------------------
  // _parseFrame  (Requirements 6.1, 8.1, 8.2, 8.3)
  // -------------------------------------------------------------------------

  /// Validates and dispatches a single complete Areyoughost frame.
  ///
  /// Frame layout:
  ///   [Magic 2B][Version 1B][Type 1B][PayloadLen 4B BE][Payload NB][CRC16 2B BE]
  void _parseFrame(Uint8List frame) {
    // Step 1: Verify header length and magic bytes [0xAE, 0x80] at bytes 0–1.
    if (frame.length < 10 || frame[0] != 0xAE || frame[1] != 0x80) {
      debugPrint('⚠️  _parseFrame: invalid frame header, dropping frame');
      return;
    }

    // Step 2: Read version and type byte
    final version = frame[2];
    final typeByte = frame[3];

    // Step 3: Read payload length from bytes 4–7 (4B big-endian u32).
    final payloadLength = (frame[4] << 24) |
        (frame[5] << 16) |
        (frame[6] << 8) |
        frame[7];

    if (frame.length < 10 + payloadLength) {
       debugPrint('⚠️  _parseFrame: incomplete frame body, dropping frame');
       return;
    }

    // Step 4: Read payload bytes starting at index 8.
    final payload = Uint8List.sublistView(frame, 8, 8 + payloadLength);

    // Step 5: Read CRC16 from end of frame.
    final crcOffset = 8 + payloadLength;
    final receivedCrc = (frame[crcOffset] << 8) | frame[crcOffset + 1];

    // Step 6: Verify CRC16-IBM-SDLC over [version][type][length_bytes_4B_BE][payload].
    final crcInput = Uint8List(1 + 1 + 4 + payloadLength);
    crcInput[0] = version;
    crcInput[1] = typeByte;
    crcInput[2] = frame[4];
    crcInput[3] = frame[5];
    crcInput[4] = frame[6];
    crcInput[5] = frame[7];
    crcInput.setAll(6, payload);

    final computedCrc = _crc16IbmSdlc(crcInput);
    if (computedCrc != receivedCrc) {
      debugPrint(
        '⚠️  _parseFrame: CRC mismatch '
        '(expected 0x${receivedCrc.toRadixString(16).padLeft(4, "0")}, '
        'got 0x${computedCrc.toRadixString(16).padLeft(4, "0")}), dropping frame',
      );
      return;
    }

    // Step 7: Dispatch to the appropriate handler based on type byte.
    final messageType = MessageType.fromByte(typeByte);
    switch (messageType) {
      case MessageType.gamePhaseChange:
        _handleGamePhaseChange(payload);
      case MessageType.gameEvent:
        _handleGameEvent(payload);
      case MessageType.roomStateSync:
        _handleRoomStateSync(payload);
      case MessageType.gameInviteReceived:
        _handleGameInviteReceived(payload);
      case MessageType.loginResponse:
        _handleLoginResponse(payload);
      case MessageType.reconnectResponse:
        _handleReconnectResponse(payload);
      default:
        // Step 8: For unhandled types, push a generic GameEvent.
        _eventController.add(GameEvent(type: messageType, payload: payload));
    }
  }

  // -------------------------------------------------------------------------
  // CRC16-IBM-SDLC (CRC-16/X-25)
  // Polynomial : 0x1021 (reflected)
  // Init       : 0xFFFF
  // Input ref  : true
  // Output ref : true
  // Final XOR  : 0xFFFF
  // -------------------------------------------------------------------------

  /// Computes CRC-16/IBM-SDLC (also known as CRC-16/X-25) over [data].
  int _crc16IbmSdlc(Uint8List data) {
    int crc = 0xFFFF;
    for (final byte in data) {
      crc ^= byte;
      for (int i = 0; i < 8; i++) {
        if ((crc & 0x0001) != 0) {
          crc = (crc >> 1) ^ 0x8408; // 0x8408 = reflected 0x1021
        } else {
          crc >>= 1;
        }
      }
    }
    return (~crc) & 0xFFFF; // final XOR 0xFFFF
  }

  // -------------------------------------------------------------------------
  // Handler stubs — full implementations in tasks 37–40
  // -------------------------------------------------------------------------

  /// Handles 0x33 GamePhaseChange. Full implementation in task 37.
  /// 
  /// Requirements 6.2, 21.1:
  /// 1. Deserialize payload into a GamePhaseChange model
  /// 2. Push a PhaseChangeEvent to _eventController
  /// 3. Start a local countdown timer from duration_secs
  /// 4. When timer hits 0, transition UI state to WAITING_FOR_SERVER (do not advance displayed phase)
  void _handleGamePhaseChange(Uint8List payload) {
    try {
      // Step 1: Deserialize payload (JSON format for Dart compatibility)
      final jsonStr = utf8.decode(payload);
      final jsonData = jsonDecode(jsonStr) as Map<String, dynamic>;
      final phaseChange = GamePhaseChange.fromJson(jsonData);

      debugPrint('📡 _handleGamePhaseChange: $phaseChange');

      // Step 2: Cancel any existing countdown timer
      _phaseCountdownTimer?.cancel();

      // Step 3: Store the current phase
      _currentPhase = phaseChange;

      // Step 4: Push PhaseChangeEvent to the event controller
      _eventController.add(PhaseChangeEvent(phaseChange: phaseChange));

      // Step 5: Start a local countdown timer from duration_secs
      // When the timer hits 0, we transition to WAITING_FOR_SERVER state
      // (The UI will display "Waiting for server..." overlay without advancing the phase)
      int remainingSeconds = phaseChange.durationSecs;

      _phaseCountdownTimer = Timer.periodic(Duration(seconds: 1), (timer) {
        remainingSeconds--;

        if (remainingSeconds <= 0) {
          // Timer expired: transition to WAITING_FOR_SERVER state
          debugPrint(
            '⏱️  Phase countdown expired for ${phaseChange.phase.displayName} '
            '(day ${phaseChange.dayNumber}). Waiting for server...',
          );

          // Push a special event to notify the UI that we're waiting for the server
          // The UI should display a "Waiting for server..." overlay
          _eventController.add(
            GameEvent(
              type: MessageType.gamePhaseChange,
              payload: Uint8List.fromList(
                utf8.encode('WAITING_FOR_SERVER'),
              ),
            ),
          );

          timer.cancel();
          _phaseCountdownTimer = null;
        }
      });

      debugPrint(
        '⏱️  Started ${phaseChange.durationSecs}s countdown for '
        '${phaseChange.phase.displayName} phase (day ${phaseChange.dayNumber})',
      );
    } catch (e, stack) {
      debugPrint('❌ _handleGamePhaseChange error: $e');
      debugPrintStack(stackTrace: stack);
      // Push raw event on error so UI can still react
      _eventController.add(
        GameEvent(type: MessageType.gamePhaseChange, payload: payload),
      );
    }
  }

  /// Handles 0x34 GameEvent. Full implementation in task 38.
  /// 
  /// Requirements 6.3:
  /// 1. Deserialize payload into a GameEvent model
  /// 2. Push to _eventController so GameScreen can display:
  ///    - Death notifications (NightResolution, VoteResult)
  ///    - Role reveals (when players die)
  ///    - Game-over screens (GameOver event with winner_faction)
  ///    - Special events (AvengerVengeance, NemesisWin, FoolWin)
  void _handleGameEvent(Uint8List payload) {
    try {
      // Step 1: Deserialize payload (JSON format for Dart compatibility)
      final jsonStr = utf8.decode(payload);
      final jsonData = jsonDecode(jsonStr) as Map<String, dynamic>;
      final gameEvent = GameEventModel.fromJson(jsonData);

      debugPrint('🎮 _handleGameEvent: $gameEvent');

      // Step 2: Push the parsed GameEvent to the event controller
      // The GameScreen will subscribe to this stream and display:
      // - Death notifications for NightResolution and VoteResult events
      // - Role reveals for each death (roleName is included in DeathInfo)
      // - Game-over screens for GameOver events with winner_faction
      // - Special event notifications for AvengerVengeance, NemesisWin, FoolWin
      _eventController.add(
        GameEvent(type: MessageType.gameEvent, payload: payload),
      );

      // Log event details for debugging
      if (gameEvent.deaths.isNotEmpty) {
        debugPrint(
          '💀 Deaths: ${gameEvent.deaths.map((d) => '${d.username} (${d.roleName})').join(', ')}',
        );
      }

      if (gameEvent.winnerFaction != null) {
        debugPrint('🏆 Winner: ${gameEvent.winnerFaction}');
      }

      if (gameEvent.extra != null) {
        debugPrint('📋 Extra data: ${gameEvent.extra}');
      }
    } catch (e, stack) {
      debugPrint('❌ _handleGameEvent error: $e');
      debugPrintStack(stackTrace: stack);
      // Push raw event on error so UI can still react
      _eventController.add(
        GameEvent(type: MessageType.gameEvent, payload: payload),
      );
    }
  }

  /// Handles 0x20 RoomStateSync. Full implementation in task 39.
  void _handleRoomStateSync(Uint8List payload) {
    try {
      // Step 1: Deserialize payload (JSON format for Dart compatibility)
      final jsonStr = utf8.decode(payload);
      final jsonData = jsonDecode(jsonStr) as Map<String, dynamic>;
      final roomSync = RoomStateSync.fromJson(jsonData);

      debugPrint('🏠 _handleRoomStateSync: $roomSync');

      // Step 2: Update the local room model with the new participant list and online statuses
      // Note: The actual room state is managed by the UI layer (GameScreen or RoomScreen)
      // This handler just deserializes and pushes the event to the stream.
      // The UI will subscribe to this event and update its local room model.

      // Step 3: Push a RoomSyncEvent to _eventController so GameScreen can update the player list
      _eventController.add(RoomSyncEvent(roomSync: roomSync));

      // Log participant details for debugging
      debugPrint(
        '👥 Room participants (${roomSync.participants.length}): '
        '${roomSync.participants.map((p) => '${p.username}${p.isOnline ? '✓' : '✗'}').join(', ')}',
      );
      debugPrint('💚 Alive count: ${roomSync.aliveCount}');
    } catch (e, stack) {
      debugPrint('❌ _handleRoomStateSync error: $e');
      debugPrintStack(stackTrace: stack);
      // Push raw event on error so UI can still react
      _eventController.add(
        GameEvent(type: MessageType.roomStateSync, payload: payload),
      );
    }
  }

  /// Handles 0x1B GameInviteReceived. Full implementation in task 40.
  void _handleGameInviteReceived(Uint8List payload) {
    try {
      // Step 1: Deserialize payload into a GameInviteReceived model
      final jsonStr = utf8.decode(payload);
      final jsonData = jsonDecode(jsonStr) as Map<String, dynamic>;
      final invite = GameInviteReceived.fromJson(jsonData);

      debugPrint('📩 _handleGameInviteReceived: $invite');

      // Step 2: New invite overwrites previous pending invite
      _pendingInvite = invite;

      // Step 3: Trigger Mail Noti sound asset playback
      _playMailNotiSound();

      // Step 4: Push an InviteEvent to _eventController so the UI shows the invite overlay
      _eventController.add(InviteEvent(invite: invite));

      debugPrint('✅ Invite from ${invite.fromUsername} for room "${invite.roomName}" pushed to UI');
    } catch (e, stack) {
      debugPrint('❌ _handleGameInviteReceived error: $e');
      debugPrintStack(stackTrace: stack);
      // Push raw event on error so UI can still react
      _eventController.add(
        GameEvent(type: MessageType.gameInviteReceived, payload: payload),
      );
    }
  }

  /// Plays the Mail Noti sound asset.
  /// 
  /// Note: This is a placeholder implementation. In a production app, you would:
  /// 1. Add a sound asset (e.g., assets/sounds/mail_noti.mp3)
  /// 2. Add an audio player package (e.g., just_audio, audioplayers)
  /// 3. Load and play the sound here
  /// 
  /// For now, we just log that the sound would be played.
  void _playMailNotiSound() {
    debugPrint('🔔 Playing Mail Noti sound (placeholder)');
    // TODO: Implement actual sound playback when audio package is added
    // Example with just_audio:
    // final player = AudioPlayer();
    // await player.setAsset('assets/sounds/mail_noti.mp3');
    // await player.play();
  }

  /// Handles 0x02 LoginResponse. Stores session_id in SharedPreferences on success.
  /// 
  /// Requirements 22.3, 26.5:
  /// 1. On successful login, store session_id in SharedPreferences
  /// 2. On reconnect, retrieve and use the stored session_id
  void _handleLoginResponse(Uint8List payload) {
    try {
      final jsonStr = utf8.decode(payload);
      final jsonData = jsonDecode(jsonStr) as Map<String, dynamic>;

      final success = jsonData['success'] as bool? ?? false;
      final sessionId = jsonData['session_id'] as String?;
      final error = jsonData['error'] as String?;

      debugPrint('🔑 _handleLoginResponse: success=$success, sessionId=${sessionId?.substring(0, 8)}...');

      if (success && sessionId != null) {
        // Store session_id in SharedPreferences for reconnection
        _storeSessionId(sessionId);
      } else if (!success && error != null) {
        debugPrint('❌ Login failed: $error');
        // Clear any stored session_id on login failure
        _clearSessionId();
      }

      _eventController.add(
        GameEvent(type: MessageType.loginResponse, payload: payload),
      );
    } catch (e, stack) {
      debugPrint('❌ _handleLoginResponse error: $e');
      debugPrintStack(stackTrace: stack);
      _eventController.add(
        GameEvent(type: MessageType.loginResponse, payload: payload),
      );
    }
  }

  /// Stores the session_id in SharedPreferences for later reconnection.
  Future<void> _storeSessionId(String sessionId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('session_id', sessionId);
      _sessionId = sessionId;
      debugPrint('💾 Stored session_id in SharedPreferences');
    } catch (e) {
      debugPrint('❌ Error storing session_id: $e');
    }
  }

  /// Retrieves the stored session_id from SharedPreferences.
  Future<String?> _retrieveSessionId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final sessionId = prefs.getString('session_id');
      if (sessionId != null) {
        _sessionId = sessionId;
        debugPrint('📖 Retrieved session_id from SharedPreferences');
        
        try {
          await connect('127.0.0.1', 8888);
        } catch (e) {
          debugPrint('🚩 Failed to auto-connect TCP server on startup: $e');
        }
      }
      return sessionId;
    } catch (e) {
      debugPrint('❌ Error retrieving session_id: $e');
      return null;
    }
  }

  /// Clears the stored session_id from SharedPreferences.
  Future<void> _clearSessionId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('session_id');
      _sessionId = null;
      debugPrint('🗑️  Cleared session_id from SharedPreferences');
    } catch (e) {
      debugPrint('❌ Error clearing session_id: $e');
    }
  }

  /// Handles 0x06 ReconnectResponse. Restores game state on success or navigates to login on failure.
  /// 
  /// Requirements 22.3, 26.5:
  /// 1. On ReconnectResponse with success=true: restore local game state and resume listener loop
  /// 2. On success=false: clear stored session_id and navigate to login screen
  void _handleReconnectResponse(Uint8List payload) {
    try {
      final jsonStr = utf8.decode(payload);
      final jsonData = jsonDecode(jsonStr) as Map<String, dynamic>;
      final response = ReconnectResponse.fromJson(jsonData);

      debugPrint('🔄 _handleReconnectResponse: success=${response.success}');

      if (response.success) {
        // Reconnection successful: restore game state
        debugPrint(
          '✅ Reconnected successfully. Restoring state: '
          'room=${response.roomId}, phase=${response.phase}, '
          'day=${response.dayNumber}, alive=${response.isAlive}',
        );

        // Restore the current phase if available
        if (response.phase != null && response.dayNumber != null && response.phaseRemainingSecs != null) {
          _currentPhase = GamePhaseChange(
            phase: response.phase!,
            dayNumber: response.dayNumber!,
            durationSecs: response.phaseRemainingSecs!,
            serverTimestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
            nightChatHistory: [],
          );

          // Restart the phase countdown timer
          _phaseCountdownTimer?.cancel();
          int remainingSeconds = response.phaseRemainingSecs!;

          _phaseCountdownTimer = Timer.periodic(Duration(seconds: 1), (timer) {
            remainingSeconds--;
            if (remainingSeconds <= 0) {
              debugPrint('⏱️  Phase countdown expired after reconnect');
              timer.cancel();
              _phaseCountdownTimer = null;
            }
          });

          debugPrint(
            '⏱️  Restarted ${response.phaseRemainingSecs}s countdown for '
            '${response.phase!.displayName} phase (day ${response.dayNumber})',
          );
        }

        // Push the reconnect response to the event stream
        _eventController.add(
          GameEvent(type: MessageType.reconnectResponse, payload: payload),
        );
      } else {
        // Reconnection failed: clear session and navigate to login
        debugPrint('❌ Reconnection failed: ${response.error}');
        _clearSessionId();

        // Push the failed response to the event stream so the UI can navigate to login
        _eventController.add(
          GameEvent(type: MessageType.reconnectResponse, payload: payload),
        );

        // Close the event controller to signal the UI to navigate to login
        if (!_eventController.isClosed) {
          _eventController.close();
        }
      }
    } catch (e, stack) {
      debugPrint('❌ _handleReconnectResponse error: $e');
      debugPrintStack(stackTrace: stack);
      _eventController.add(
        GameEvent(type: MessageType.reconnectResponse, payload: payload),
      );
    }
  }

  // -------------------------------------------------------------------------
  // init
  // -------------------------------------------------------------------------

  /// Initializes the NetworkService by retrieving any stored session_id.
  /// This is called during app startup to restore previous session if available.
  Future<void> init() async {
    try {
      debugPrint('🔧 Initializing NetworkService...');
      await _retrieveSessionId();
      debugPrint('✅ NetworkService initialized');
    } catch (e) {
      debugPrint('❌ Error initializing NetworkService: $e');
      rethrow;
    }
  }

  // -------------------------------------------------------------------------
  // disconnect
  // -------------------------------------------------------------------------

  /// Gracefully closes the socket and cleans up state.
  /// Clears the stored session_id to prevent automatic reconnection.
  void disconnect() {
    _phaseCountdownTimer?.cancel();
    _phaseCountdownTimer = null;
    _clearSessionId();
    _handleDisconnect();
  }

  // -------------------------------------------------------------------------
  // Legacy invite helpers (kept for UI compatibility — task 40 will replace)
  // -------------------------------------------------------------------------

  /// Accept a game invite. Full implementation in task 40.
  Future<void> acceptInvite(String inviteCode) async {
    debugPrint('📩 acceptInvite: $inviteCode (stub — task 40)');
  }

  /// Decline a game invite. Full implementation in task 40.
  Future<void> declineInvite(String inviteCode) async {
    debugPrint('🚫 declineInvite: $inviteCode (stub — task 40)');
  }
}
