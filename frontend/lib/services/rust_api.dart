import 'package:areyoughost/src/rust/api.dart'; // Import generated bindings
import 'package:areyoughost/src/rust/frb_generated.dart'; // Import RustLib

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

    // Initialize the Rust Api object. FFI no longer drives the DB.
    try {
      await RustLib.init(); // Initialize FRB
      _api = await Api.newInstance(databaseUrl: "");
      print('Rust API initialized (No local DB bridge required)');
    } catch (e) {
      print('Failed to initialize Rust API: $e');
      rethrow;
    }
  }
}
