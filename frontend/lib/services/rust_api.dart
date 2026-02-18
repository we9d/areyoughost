import 'package:areyoughost/src/rust/api.dart'; // Import generated bindings
import 'package:areyoughost/src/rust/frb_generated.dart'; // Import RustLib
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';

class RustApi {
  static Api? _api;

  static Api get instance {
    if (_api == null) {
      throw Exception('RustApi not initialized. Call init() first.');
    }
    return _api!;
  }

  static Future<void> init() async {
    if (_api != null) return;

    // For local Docker Postgres, use default connection string
    // In production, this should come from config/env
    // Android emulator needs 10.0.2.2 to access host localhost
    // iOS simulator uses localhost
    // Windows uses localhost
    // We can detecting platform to switch string if needed, 
    // but for Windows dev:

    // const connectionString = "postgres://postgres:password@localhost/areyoughost";
    const connectionString = "postgres://postgres:password@localhost:5433/areyoughost";

    // Initialize the Rust Api object
    try {
      await RustLib.init(); // Initialize FRB
      _api = await Api.newInstance(databaseUrl: connectionString);
      print('Rust API initialized with DB: $connectionString');
    } catch (e) {
      print('Failed to initialize Rust API: $e');
      rethrow;
    }
  }
}
