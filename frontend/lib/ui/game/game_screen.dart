import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:areyoughost/services/rust_api.dart'; // Import Rust API
import 'package:areyoughost/src/rust/api.dart'; // Import generated bindings (models)
import 'package:areyoughost/src/rust/models.dart'; // Import models explicitly
import 'package:areyoughost/services/session_manager.dart';

class GameScreen extends StatefulWidget {
  final String roomId;
  const GameScreen({super.key, required this.roomId});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  // Real Data
  List<dynamic> _participants = []; // Will hold JSON derived mock for now or real struct
  // Note: generate_api returns models. We need to parse json from get_game_state or use stream
  // For prototype, get_game_state returns JSON string.

  List<ChatMessage> _messages = [];
  Timer? _pollTimer;
  String _currentPhase = "Waiting";
  int _remainingTime = 0;
  String? _myUserId;
  final TextEditingController _chatController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadCurrentUser();
    _startPolling();
  }

  Future<void> _loadCurrentUser() async {
    final userId = await SessionManager.getUserId();
    setState(() {
      _myUserId = userId;
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _chatController.dispose();
    super.dispose();
  }

  void _startPolling() {
    _pollTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      await _fetchGameState();
    });
  }

  Future<void> _fetchGameState() async {
    try {
      // 1. Get Game State (JSON)
      final jsonString = await RustApi.instance.getGameState();
      final data = json.decode(jsonString);

      setState(() {
        _currentPhase = data['phase'];
        _remainingTime = data['remaining_time'];
      });

      // Note: For now, participants are not in this JSON, we might need a separate call 
      // or update get_game_state in Rust to include them.
      // API.rs start_game initializes 6 mock players in Rust state.
      // We should probably add a get_participants method or include in state JSON.
      // For this step, I'll rely on the fact that I can't easily get them without updating Rust again.
      // I will trust the phase timer works.

    } catch (e) {
      // print('Polling error: $e'); // Expected if game not started or error
    }
  }

  Future<void> _sendMessage() async {
    if (_chatController.text.trim().isEmpty || _myUserId == null) return;

    final msgText = _chatController.text.trim();
    _chatController.clear();

    try {
      final chatMsg = await RustApi.instance.sendMessage(
        roomId: widget.roomId,
        userId: _myUserId!,
        message: msgText,
      );

      setState(() {
        _messages.add(chatMsg);
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to send: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Room ${widget.roomId}'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _fetchGameState),
        ],
      ),
      body: Column(
        children: [
          // Game Phase Timer / Status
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            color: Colors.amber.withOpacity(0.1),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("Phase: $_currentPhase", style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)),
                Text("$_remainingTime s", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              ],
            ),
          ),
          
          // Placeholder for Participants (until we update Rust to return them)
          const Expanded(
            flex: 2,
            child: Center(child: Text("Participants View (Coming Soon)")), 
          ),
          
          const Divider(height: 1),
          // Chat Area
          Expanded(
            flex: 2,
            child: Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      return _buildchatMessage(_messages[index]);
                    },
                  ),
                ),
                _buildChatInput(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildchatMessage(ChatMessage msg) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: '${msg.senderName}: ',
              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueAccent),
            ),
            TextSpan(
              text: msg.message,
              style: const TextStyle(color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChatInput() {
    return Container(
      padding: const EdgeInsets.all(8),
      color: Theme.of(context).cardColor,
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _chatController,
              decoration: InputDecoration(
                hintText: 'Say something...',
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                fillColor: Colors.black12,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
              ),
              onSubmitted: (_) => _sendMessage(),
            ),
          ),
          const SizedBox(width: 8),
          CircleAvatar(
            backgroundColor: Theme.of(context).primaryColor,
            child: IconButton(
              icon: const Icon(Icons.send, size: 18),
              onPressed: _sendMessage,
            ),
          ),
        ],
      ),
    );
  }
}
