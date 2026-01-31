import 'package:flutter/material.dart';
import 'package:areyoughost/models/mock_models.dart';
import 'package:areyoughost/ui/game/game_screen.dart';

class LobbyScreen extends StatefulWidget {
  const LobbyScreen({super.key});

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  // Mock data
  final List<Room> rooms = [
    Room(roomId: '101', roomName: "Beginner's Den", maxPlayers: 16, currentPlayers: 12, isPublic: true, status: 'waiting'),
    Room(roomId: '102', roomName: "Ranked Match #552", maxPlayers: 16, currentPlayers: 16, isPublic: true, status: 'playing'),
    Room(roomId: '103', roomName: "Chill & Fun", maxPlayers: 8, currentPlayers: 3, isPublic: true, status: 'waiting'),
    Room(roomId: '104', roomName: "Role Practice", maxPlayers: 12, currentPlayers: 10, isPublic: false, status: 'waiting'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Lobby'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {},
          ),
        ],
      ),
      body: Column(
        children: [
          _buildQuickPlayBanner(context),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: rooms.length,
              itemBuilder: (context, index) {
                final room = rooms[index];
                return _buildRoomCard(context, room);
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
            // Navigate to creating a room (mock)
            Navigator.push(context, MaterialPageRoute(builder: (context) => const GameScreen(roomId: 'new_room')));
        },
        label: const Text('Create Room'),
        icon: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildQuickPlayBanner(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
        border: Border(bottom: BorderSide(color: Theme.of(context).colorScheme.primary.withOpacity(0.2))),
      ),
      child: Column(
        children: [
          const Text(
            'Ready to hunt?',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: () {
               Navigator.push(context, MaterialPageRoute(builder: (context) => const GameScreen(roomId: 'quick_play')));
            },
            child: const Text('QUICK PLAY'),
          ),
        ],
      ),
    );
  }

  Widget _buildRoomCard(BuildContext context, Room room) {
    final isFull = room.currentPlayers >= room.maxPlayers;
    final isPlaying = room.status == 'playing';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () {
          if (!isFull) {
            Navigator.push(context, MaterialPageRoute(builder: (context) => GameScreen(roomId: room.roomId)));
          }
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: isPlaying ? Colors.red.withOpacity(0.2) : Colors.green.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isPlaying ? Icons.sports_esports : Icons.meeting_room,
                  color: isPlaying ? Colors.red : Colors.green,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      room.roomName,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (!room.isPublic) const Padding(
                          padding: EdgeInsets.only(right: 8),
                          child: Icon(Icons.lock, size: 14, color: Colors.grey),
                        ),
                        Text(
                          '${room.currentPlayers}/${room.maxPlayers} Players',
                          style: TextStyle(color: Colors.grey[400], fontSize: 12),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (isPlaying)
                Chip(label: const Text('Playing'), backgroundColor: Colors.red.withOpacity(0.2), labelStyle: const TextStyle(fontSize: 10))
              else if (isFull)
                const Chip(label: Text('Full'))
              else
                const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}
