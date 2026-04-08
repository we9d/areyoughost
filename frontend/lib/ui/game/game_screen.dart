import 'dart:async';

import 'package:flutter/material.dart';

import 'package:areyoughost/models/mock_models.dart' hide RoleInfo, SkillOption, ChatMessage;
import 'package:areyoughost/models/view_models.dart';
import 'package:areyoughost/models/room_model.dart';
import 'package:areyoughost/services/session_manager.dart';
import 'package:areyoughost/services/auth_service.dart';
import 'package:areyoughost/src/rust/frb_generated.dart';
import 'package:areyoughost/src/rust/api.dart';
import 'package:areyoughost/src/rust/models.dart' as rust;
import 'package:areyoughost/src/rust/game_logic/roles.dart'; // Add SkillType
import 'package:areyoughost/services/rust_api.dart';

import 'package:areyoughost/ui/dialogs/role_info_dialog.dart';
import 'package:areyoughost/ui/dialogs/skill_select_dialog.dart';
import 'package:areyoughost/ui/game/dialogs/skill_popup_choice.dart';
import 'package:areyoughost/ui/game/dialogs/skill_popup_result.dart';
import 'package:areyoughost/ui/game/dialogs/skill_popup_single.dart';
import 'package:areyoughost/ui/widgets/roles_card.dart';
import 'package:areyoughost/models/role_model.dart';
import 'package:areyoughost/services/game_data_service.dart';

import 'package:areyoughost/ui/game/widgets/DayTimeAnimation.dart';
import 'package:areyoughost/ui/game/widgets/NightTimeAnimation.dart';
import 'package:areyoughost/ui/game/widgets/chat_box.dart';
import 'package:areyoughost/ui/game/widgets/chat_input_row.dart';
import 'package:areyoughost/ui/game/widgets/exit_game_popup.dart';
import 'package:areyoughost/ui/game/widgets/game_top_bar.dart';
import 'package:areyoughost/ui/game/widgets/player_grid_day.dart';
import 'package:areyoughost/ui/game/widgets/player_grid_night.dart';
import 'package:areyoughost/ui/game/widgets/players_popup.dart';
import 'package:areyoughost/ui/Invite_friend/invite_panel.dart';
import 'package:areyoughost/ui/game/random_role_screen.dart';

/// Timer synchronization state for UI
enum TimerState {
  /// Local countdown is running and in sync with server
  COUNTING_DOWN,
  /// Local countdown reached 0, waiting for server 0x33 GamePhaseChange
  WAITING_FOR_SERVER,
}

class GameScreen extends StatefulWidget {
  /// Pass room from Quick Play or from game.started event.
  /// If null, roomId is used as fallback (e.g. from WaitingRoom path).
  final RoomModel? initialRoom;
  final String roomId;
  final String? role;

  const GameScreen({
    super.key,
    this.initialRoom,
    required this.roomId,
    this.role,
  });

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  // 16 fixed slots — index 0 = slot 1, etc.
  final List<String?> _slots = List.filled(16, null);

  RoomModel? _room;
  Timer? _timer;
  List<ChatMessageVM> chatMessages = [];
  
  String? _myRoleCode;
  SkillData? _selectedSkill;
  bool _isTargeting = false;
  bool _isSubmitting = false;

  int? mySlot; // 1-based slot number that belongs to this player
  int? selectedTarget; // slot number being voted on
  final Set<String> _deadPlayerIds = {};
  
  /// Timer synchronization state: tracks whether local countdown is in sync or waiting for server
  TimerState _timerState = TimerState.COUNTING_DOWN;
  
  bool get isDay {
    if (_room == null || _room!.isLobby) return true;
    return _room!.currentPhase == 'Day' || _room!.currentPhase == 'Vote';
  }

  String _countdownText = "--:--";

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _handleStartGame() async {
    if (_isSubmitting) return;
    setState(() => _isSubmitting = true);
    try {
      await RustApi.instance.startGame(roomId: widget.roomId);
    } catch (e) {
      _showError("Failed to start: $e");
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _handleCastVote(String targetId) async {
    if (_isSubmitting) return;
    setState(() => _isSubmitting = true);
    try {
      await RustApi.instance.castVote(roomId: widget.roomId, targetId: targetId);
    } catch (e) {
      _showError("Failed to vote: $e");
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _handleUseSkill(String targetId, String skillCode) async {
    if (_isSubmitting) return;
    
    // Map skillCode to SkillType
    SkillType? skillType;
    switch (skillCode.toUpperCase()) {
      case 'GHOST_KILL':   skillType = SkillType.kill; break;
      case 'DOCTOR_HEAL':  skillType = SkillType.protect; break;
      case 'SEER_INSPECT': skillType = SkillType.checkFaction; break;
      case 'POLICE_INSPECT': skillType = SkillType.checkFaction; break;
      case 'UNDERTAKER_CHECK': skillType = SkillType.viewDead; break;
      case 'MONK_BLOCK':   skillType = SkillType.block; break;
      default:
        // Try fallback if the code matches enum name exactly (lowerCase)
        skillType = SkillType.values.firstWhere(
          (e) => e.name.toLowerCase() == skillCode.toLowerCase(),
          orElse: () => SkillType.special
        );
    }

    setState(() => _isSubmitting = true);
    try {
      await RustApi.instance.submitAction(
        roomId: widget.roomId, 
        actionType: skillType!, 
        targetId: targetId
      );
    } catch (e) {
      _showError("Skill failed: $e");
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _handleSendMessage(String text) async {
    if (_isSubmitting || text.trim().isEmpty) return;
    try {
      await RustApi.instance.sendMessage(roomId: widget.roomId, messageText: text);
    } catch (e) {
      _showError("Failed to send: $e");
    }
  }

  @override
  void initState() {
    super.initState();
    _room = widget.initialRoom;
    if (_room != null) {
      _applyRoomPlayers(_room!.players);
    }
    _startTimer();
    chatMessages = [];
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      _updateCountdownText();
    });
  }

  void _updateCountdownText() {
    if (_room == null) return;
    
    DateTime? targetTime;
    if (_room!.isLobby && _room!.autoStartAt != null) {
      targetTime = DateTime.parse(_room!.autoStartAt!).toLocal();
    } else if (_room!.status == 'PLAYING' && _room!.phaseEndTime != null) {
      targetTime = DateTime.fromMillisecondsSinceEpoch(_room!.phaseEndTime! * 1000).toLocal();
    }

    if (targetTime == null) {
      setState(() => _countdownText = "--:--");
      return;
    }

    final now = DateTime.now();
    final diff = targetTime.difference(now);

    if (diff.isNegative) {
      setState(() {
        _countdownText = "00:00";
        if (_timerState == TimerState.COUNTING_DOWN) {
          _timerState = TimerState.WAITING_FOR_SERVER;
        }
      });
      return;
    }

    final mins = diff.inMinutes.toString().padLeft(2, '0');
    final secs = (diff.inSeconds % 60).toString().padLeft(2, '0');
    setState(() => _countdownText = "$mins:$secs");
  }

  void _applyRoomPlayers(List<PlayerInfo> players) {
    SessionManager.getSession().then((session) {
      final myId = session?['userId'] ?? '';
      setState(() {
        for (int i = 0; i < 16; i++) _slots[i] = null;
        for (int i = 0; i < players.length && i < 16; i++) {
          _slots[i] = players[i].username;
          if (players[i].playerId == myId) mySlot = i + 1;
        }
      });
    });
  }

  void _addPlayer(String username, String playerId) {
    SessionManager.getSession().then((session) {
      final myId = session?['userId'] ?? '';
      setState(() {
        final idx = _slots.indexWhere((s) => s == null);
        if (idx != -1) {
          _slots[idx] = username;
          if (playerId == myId) mySlot = idx + 1;
        }
      });
    });
  }

  void _removePlayer(String username) {
    setState(() {
      final idx = _slots.indexWhere((s) => s == username);
      if (idx != -1) _slots[idx] = null;
    });
  }

  void _showDeathNotification(List<dynamic> diedIds, {bool isNight = true}) {
    setState(() {
      for (var id in diedIds) {
        _deadPlayerIds.add(id.toString());
      }
    });

    String message = isNight 
      ? (diedIds.length == 1 ? 'มีคนเสียชีวิตเมื่อคืนนี้ 1 ศพ' : 'มีคนเสียชีวิตเมื่อคืนนี้ ${diedIds.length} ศพ')
      : (diedIds.length == 1 ? 'ผู้เล่นถูกประหารชีวิตแล้ว' : 'มีผู้เล่นเสียชีวิต ${diedIds.length} คน');
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: isNight ? Colors.redAccent : Colors.orangeAccent,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showGameOverDialog(String winner) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Center(
          child: Text('จบเกม!', 
            style: TextStyle(color: Colors.orangeAccent, fontSize: 28, fontWeight: FontWeight.bold)
          )
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('ฝ่ายที่ชนะคือ:', style: TextStyle(color: Colors.white70)),
            const SizedBox(height: 10),
            Text(winner.toUpperCase(), 
              style: TextStyle(
                color: winner.toLowerCase() == 'ghost' ? Colors.red : Colors.greenAccent,
                fontSize: 32, 
                fontWeight: FontWeight.w900,
                letterSpacing: 2
              )
            ),
          ],
        ),
        actions: [
          Center(
            child: ElevatedButton(
              onPressed: () {
                Navigator.of(context).popUntil((route) => route.isFirst);
              },
              child: const Text('กลับสู่หน้าหลัก'),
            ),
          )
        ],
      ),
    );
  }

  List<PlayerModel> get _playerModels => List.generate(16, (i) {
        final username = _slots[i];
        return PlayerModel(
          number: i + 1,
          name: username ?? '',
          isAlive: username != null && !_deadPlayerIds.contains(username),
        );
      });

  void openPlayersPopup() {
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => PlayersPopup(
        players: _slots
            .asMap()
            .entries
            .where((e) => e.value != null)
            .map((e) => 'ห้อง${e.key + 1} ${e.value}')
            .toList(),
      ),
    );
  }

  void openSkillDialog() {
    if (_myRoleCode == null) return;
    
    final currentPhase = _room?.currentPhase?.toUpperCase() ?? 'DAY';
    
    final availableSkills = GameDataService.skills.where((s) {
      if (s.phase == 'ANY') return true;
      return s.phase == currentPhase;
    }).toList();

    if (availableSkills.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ไม่มีสกิลที่ใช้งานได้ในขณะนี้')),
      );
      return;
    }

    if (availableSkills.length >= 2) {
      showDialog(
        context: context,
        barrierColor: Colors.black54,
        builder: (_) => SkillPopupChoice(
          skill1Name: availableSkills[0].skillName,
          skill1Description: availableSkills[0].description ?? '',
          skill1Image: availableSkills[0].imagePath ?? 'assets/images/skill_eye.png',
          skill2Name: availableSkills[1].skillName,
          skill2Description: availableSkills[1].description ?? '',
          skill2Image: availableSkills[1].imagePath ?? 'assets/images/skill_heal.png',
          onSkill1: () {
            Navigator.pop(context);
            _handleSkillUsed(availableSkills[0]);
          },
          onSkill2: () {
            Navigator.pop(context);
            _handleSkillUsed(availableSkills[1]);
          },
          onClose: () => Navigator.pop(context),
        ),
      );
    } else {
      showDialog(
        context: context,
        barrierColor: Colors.black54,
        builder: (_) => SkillPopupSingle(
          skillName: availableSkills[0].skillName,
          description: availableSkills[0].description ?? '',
          image: availableSkills[0].imagePath ?? 'assets/images/skill_eye.png',
          onUse: () {
            _handleSkillUsed(availableSkills[0]);
          },
        ),
      );
    }
  }

  void _handleSkillUsed(SkillData skill) {
    setState(() {
      _selectedSkill = skill;
      _isTargeting = true;
      selectedTarget = null;
    });
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('คุณเลือกใช้: ${skill.skillName}\nกรุณาเลือกเป้าหมายในตารางผู้เล่น'),
        backgroundColor: Colors.blueGrey,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void onPlayerTap(int number) {
    if (number == (mySlot ?? -1)) return;
    
    if (_isTargeting && _selectedSkill != null) {
      setState(() => selectedTarget = number);
      _confirmSkillUsage(number);
    } else {
      setState(() => selectedTarget = number);
    }
  }

  void _confirmSkillUsage(int targetNumber) {
    final targetName = _slots[targetNumber - 1] ?? 'ผู้เล่น $targetNumber';
    
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF2C2C2C),
        title: Text('ยืนยันการใช้ ${_selectedSkill!.skillName}', style: const TextStyle(color: Colors.white)),
        content: Text('คุณต้องการใช้สกิลนี้กับ $targetName หรือไม่?', style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ยกเลิก', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _executeSkillAction(targetNumber.toString(), _selectedSkill!.skillName);
            },
            child: const Text('ยืนยัน'),
          ),
        ],
      ),
    );
  }

  void _executeSkillAction(String targetId, String skillCode) {
    _handleUseSkill(targetId, skillCode);

    setState(() {
      _isTargeting = false;
      _selectedSkill = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenH = MediaQuery.of(context).size.height;
    final players = _playerModels;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Container(
          width: 390,
          height: screenH > 844 ? 844 : screenH,
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(24),
          ),
          clipBehavior: Clip.hardEdge,
          child: Stack(
            children: [
              /// Background
              Positioned.fill(
                child: Image.asset(
                  isDay ? 'assets/images/DayTimeBg.jpg' : 'assets/images/NightTimeBg.jpg',
                  fit: BoxFit.cover,
                ),
              ),

              /// Main UI
              Positioned.fill(
                child: Column(
                  children: [
                    /// Top Bar
                    GameTopBar(
                      title: (_room?.isLobby ?? true) 
                          ? 'รอผู้เล่น... $_countdownText' 
                          : (isDay ? 'เวลากลางวัน $_countdownText' : 'เวลากลางคืน $_countdownText'),
                      onExitTap: () => showDialog(
                        context: context,
                        builder: (_) => ExitGamePopup(
                          onConfirm: () async {
                            try {
                              await RustApi.instance.leaveRoom(roomId: widget.roomId);
                            } catch (e) {
                              debugPrint("Leave room error: $e");
                            }
                            if (mounted) {
                              Navigator.pop(context); // Final pop to exit GameScreen
                            }
                          },
                        ),
                      ),
                      onPlayerTap: openPlayersPopup,
                    ),

                    const SizedBox(height: 6),

                    /// Player Grid or Lobby View
                    Expanded(
                      flex: 5,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: (_room?.isLobby ?? true)
                            ? _buildLobbyView()
                            : (isDay
                                ? PlayerGridDay(
                                    players: players,
                                    myPlayerNumber: mySlot ?? 0,
                                    selectedTarget: selectedTarget,
                                    isVotePhase: _room?.currentPhase == 'Vote',
                                    onPlayerTap: (pid) {
                                      if (_room?.currentPhase == 'Vote') {
                                        _handleCastVote(pid.toString());
                                      }
                                    },
                                  )
                                : PlayerGridNight(
                                    players: players,
                                    myPlayerNumber: mySlot ?? 0,
                                    selectedTarget: selectedTarget,
                                    isVotePhase: false,
                                    onPlayerTap: onPlayerTap,
                                  )),
                      ),
                    ),

                    const SizedBox(height: 2),

                    /// Chat Box
                    SizedBox(
                      height: 220,
                      child: ChatBox(messages: chatMessages),
                    ),

                    const SizedBox(height: 4),

                    /// Chat Input
                    ChatInputRow(
                      onRoleInfoTap: () => showDialog(
                        context: context,
                        builder: (_) => const RolesDialog(),
                      ),
                      onSkillTap: openSkillDialog,
                      onSend: _handleSendMessage,
                    ),

                    const SizedBox(height: 10),
                  ],
                ),
              ),

              /// Day Animation
              if (isDay)
                const Positioned.fill(
                  child: IgnorePointer(
                    child: Center(child: DayTimeAnimation()),
                  ),
                ),

              /// Night Animation
              if (!isDay)
                const Positioned.fill(
                  child: IgnorePointer(
                    child: Center(child: NightTimeAnimation()),
                  ),
                ),

              /// Waiting for Server Overlay
              if (_timerState == TimerState.WAITING_FOR_SERVER && !(_room?.isLobby ?? true))
                Positioned.fill(
                  child: Container(
                    color: Colors.black.withOpacity(0.7),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(
                            width: 50,
                            height: 50,
                            child: CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.orangeAccent),
                              strokeWidth: 3,
                            ),
                          ),
                          const SizedBox(height: 20),
                          const Text(
                            'Waiting for server...',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
  Widget _buildLobbyView() {
    final connectedCount = _slots.where((s) => s != null).length;
    final isHost = _room?.ownerId != null && _room?.ownerId.isNotEmpty == true; // Simplification

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          _room?.roomType == 'QUICK' ? 'Quick Play' : 'Private Room',
          style: const TextStyle(color: Colors.white70, fontSize: 16),
        ),
        const SizedBox(height: 8),
        Text(
          '$connectedCount / ${_room?.maxPlayers ?? 16} Players',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        if (_room?.roomType == 'QUICK') ...[
          const SizedBox(height: 20),
          const Text(
            'เวลากลางวัน',
            style: TextStyle(color: Colors.white60, fontSize: 14),
          ),
          Text(
            _countdownText,
            style: const TextStyle(
              color: Colors.orangeAccent,
              fontSize: 48,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
            ),
          ),
        ],
        const SizedBox(height: 30),
        if (_room?.roomType == 'PRIVATE') 
           Padding(
             padding: const EdgeInsets.only(top: 20),
             child: ElevatedButton(
               onPressed: () {
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (_) => InvitePanel(inviteCode: widget.roomId),
                  );
               },
               child: const Text('Invite Friends'),
             ),
           ),
        if (_room?.roomType == 'PRIVATE' && isHost)
           Padding(
             padding: const EdgeInsets.only(top: 10),
             child: ElevatedButton(
               style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
               onPressed: _isSubmitting ? null : _handleStartGame,
               child: const Text('Start Game Now'),
             ),
           ),
      ],
    );
  }
}