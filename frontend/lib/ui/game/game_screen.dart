import 'package:flutter/material.dart';
import 'package:areyoughost/models/mock_models.dart';

class GameScreen extends StatefulWidget {
  final String roomId;
  const GameScreen({super.key, required this.roomId});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  // Mock Data
  final List<GameParticipant> players = List.generate(
    16,
    (index) => GameParticipant(
      userId: 'user_$index',
      username: 'Player ${index + 1}',
      seatNumber: index,
      isAlive: index > 2, // First 3 are dead
      role: index == 0 ? Role(roleId: 1, roleName: 'Seer', faction: 'villager', description: 'Can check roles') : null,
    ),
  );

  final List<ChatMessage> messages = [
    ChatMessage(messageId: '1', senderId: 'user_5', senderName: 'Player 6', message: 'I think Player 1 is sus', phaseType: 'day', createdAt: DateTime.now().subtract(const Duration(minutes: 5))),
    ChatMessage(messageId: '2', senderId: 'user_1', senderName: 'Player 2', message: 'Why me? I was afk', phaseType: 'day', createdAt: DateTime.now().subtract(const Duration(minutes: 4))),
    ChatMessage(messageId: '3', senderId: 'user_8', senderName: 'Player 9', message: 'Skip vote?', phaseType: 'day', createdAt: DateTime.now().subtract(const Duration(minutes: 2))),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Day 1 - Discussion'),
        actions: [
          IconButton(icon: const Icon(Icons.info_outline), onPressed: () {}),
        ],
      ),
      body: Column(
        children: [
          // Game Phase Timer / Status
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            color: Colors.amber.withOpacity(0.1),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("🌞 Day Phase", style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)),
                Text("00:45", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              ],
            ),
          ),
          // Player Grid
          Expanded(
            flex: 2,
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Calculate ideal count based on width (approx 80-90px per item)
                int crossAxisCount = (constraints.maxWidth / 90).floor().clamp(3, 5);
                return GridView.builder(
                  padding: const EdgeInsets.all(8),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    childAspectRatio: 0.8,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemCount: players.length,
                  itemBuilder: (context, index) {
                    return _buildPlayerAvatar(players[index]);
                  },
                );
              },
            ),
          ),
          const Divider(height: 1),
          // Chat Area
          Expanded(
            flex: 1,
            child: Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      return _buildchatMessage(messages[index]);
                    },
                  ),
                ),
                _buildChatInput(),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: BottomAppBar(
        color: Theme.of(context).cardColor,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            IconButton(icon: const Icon(Icons.note_alt_outlined), tooltip: 'Notes', onPressed: () {}),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () {},
              child: const Text('VOTE'),
            ),
            IconButton(icon: const Icon(Icons.backpack_outlined), tooltip: 'Inventory', onPressed: () {}),
          ],
        ),
      ),
    );
  }

  Widget _buildPlayerAvatar(GameParticipant player) {
    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: player.isAlive ? Colors.grey[800] : Colors.grey[900],
                  border: Border.all(
                    color: player.role != null ? Colors.blue : Colors.transparent, // Highlight self
                    width: 2,
                  ),
                  image: const DecorationImage(
                    image: NetworkImage("https://api.dicebear.com/7.x/avataaars/png?seed=custom-seed"), // Placeholder
                    // In real app, use asset or local generation
                  ),
                ),
                child: !player.isAlive
                    ? Container(
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.7),
                          shape: BoxShape.circle,
                        ),
                        child: const Center(child: Icon(Icons.close, color: Colors.red, size: 32)),
                      )
                    : null,
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: CircleAvatar(
                  radius: 10,
                  backgroundColor: Colors.white,
                  child: Text(
                    '${player.seatNumber + 1}',
                    style: const TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          player.username,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 10,
            color: player.isAlive ? Colors.white : Colors.grey, 
            decoration: player.isAlive ? null : TextDecoration.lineThrough,
          ),
        ),
      ],
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
              decoration: InputDecoration(
                hintText: 'Say something...',
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                fillColor: Colors.black12,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
              ),
            ),
          ),
          const SizedBox(width: 8),
          CircleAvatar(
            backgroundColor: Theme.of(context).primaryColor,
            child: IconButton(
              icon: const Icon(Icons.send, size: 18),
              onPressed: () {},
            ),
          ),
        ],
      ),
    );
  }
}
