/// Rust API Service Layer
///
/// This service provides the interface between the Flutter frontend and
/// the Rust backend core engine via FFI (Foreign Function Interface).
///
/// Currently using mock implementations while the flutter_rust_bridge
/// integration is being completed. Once FFI is fully set up, these methods
/// will call the actual Rust functions from the core library.
///
/// Architecture:
/// Flutter UI -> RustApi (this file) -> FFI Bridge -> Rust Core Engine

import 'package:areyoughost/models/mock_models.dart';

/// Singleton service for communicating with the Rust backend
///
/// Provides methods for:
/// - User authentication (login/register)
/// - Room management (list/create/join)
/// - Game actions (chat/voting)
class RustApi {
  // Singleton pattern
  static final RustApi _instance = RustApi._internal();
  factory RustApi() => _instance;
  RustApi._internal();

  // Mock implementations - will be replaced with actual FFI calls
  Future<User?> login(String username, String password) async {
    // TODO: Call Rust via FFI
    await Future.delayed(const Duration(milliseconds: 500));
    return User(
      userId: '1',
      username: username,
      displayName: username,
    );
  }

  Future<User?> register(String username, String password) async {
    // TODO: Call Rust via FFI
    await Future.delayed(const Duration(milliseconds: 500));
    return User(
      userId: '1',
      username: username,
      displayName: username,
    );
  }

  Future<List<Room>> getRooms() async {
    // TODO: Call Rust via FFI
    await Future.delayed(const Duration(milliseconds: 300));
    return [
      Room(
        roomId: '101',
        roomName: "Beginner's Den",
        maxPlayers: 16,
        currentPlayers: 12,
        isPublic: true,
        status: 'waiting',
      ),
      Room(
        roomId: '102',
        roomName: "Ranked Match #552",
        maxPlayers: 16,
        currentPlayers: 16,
        isPublic: true,
        status: 'playing',
      ),
    ];
  }

  Future<Room> createRoom(String roomName, int maxPlayers) async {
    // TODO: Call Rust via FFI
    await Future.delayed(const Duration(milliseconds: 500));
    return Room(
      roomId: 'new_${DateTime.now().millisecondsSinceEpoch}',
      roomName: roomName,
      maxPlayers: maxPlayers,
      currentPlayers: 1,
      isPublic: true,
      status: 'waiting',
    );
  }

  Future<void> sendMessage(String roomId, String message) async {
    // TODO: Call Rust via FFI
    await Future.delayed(const Duration(milliseconds: 100));
  }

  Future<void> castVote(String roomId, String targetUserId) async {
    // TODO: Call Rust via FFI
    await Future.delayed(const Duration(milliseconds: 200));
  }
}
