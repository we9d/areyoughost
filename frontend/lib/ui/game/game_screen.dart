import 'dart:async';

import 'package:flutter/material.dart';

import 'package:areyoughost/models/mock_models.dart' hide RoleInfo;
import 'package:areyoughost/game/game_catalog.dart';
import 'package:areyoughost/services/auth_service.dart';
import 'package:areyoughost/services/role_service.dart';
import 'package:areyoughost/services/ws_service.dart';
import 'package:areyoughost/ui/game/dialogs/skill_popup_choice.dart';
import 'package:areyoughost/ui/game/dialogs/skill_popup_result.dart';
import 'package:areyoughost/ui/game/dialogs/skill_popup_single.dart';
import 'package:areyoughost/ui/game/widgets/DayTimeAnimation.dart';
import 'package:areyoughost/ui/game/widgets/NightTimeAnimation.dart';
import 'package:areyoughost/ui/game/widgets/chat_box.dart';
import 'package:areyoughost/ui/game/widgets/chat_input_row.dart';
import 'package:areyoughost/ui/game/widgets/exit_game_popup.dart';
import 'package:areyoughost/ui/game/widgets/game_top_bar.dart';
import 'package:areyoughost/ui/game/game_started_roles.dart';
import 'package:areyoughost/ui/game/widgets/player_grid_day.dart';
import 'package:areyoughost/ui/game/widgets/player_grid_night.dart';
import 'package:areyoughost/ui/game/widgets/players_popup.dart';
import 'package:areyoughost/ui/game/role_deck.dart';
import 'package:areyoughost/ui/result/ghosts-win.dart';
import 'package:areyoughost/ui/result/ghosts-defeat.dart';
import 'package:areyoughost/ui/result/serialkiller-defeat.dart';
import 'package:areyoughost/ui/result/serialkiller-win.dart';
import 'package:areyoughost/ui/result/spirit-defeat.dart';
import 'package:areyoughost/ui/result/spirit-win.dart';
import 'package:areyoughost/ui/result/villagers-defeat.dart';
import 'package:areyoughost/ui/result/villagers-win.dart';
import 'package:areyoughost/ui/widgets/role_dropdown_card.dart';

class GameScreen extends StatefulWidget {
  final String roomId;
  final String? role;
  final List<String>? roomRolePool;
  final List<String>? playerNamesInJoinOrder;
  final Map<String, String>? serverRolesByPlayerId;
  final String? initialPhase;
  final int? initialPhaseDeadlineAt;

  const GameScreen({
    super.key,
    required this.roomId,
    this.role,
    this.roomRolePool,
    this.playerNamesInJoinOrder,
    this.serverRolesByPlayerId,
    this.initialPhase,
    this.initialPhaseDeadlineAt,
  });

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  late List<PlayerModel> players;
  late List<ChatMessage> chatMessages;
  late List<SkillOption> currentRoleSkills;
  late Map<int, bool> _aliveByPlayerNumber;
  late Map<int, String> _roleByPlayerNumber;
  final Map<String, RoleDisplayItem> _roleCatalogByName = <String, RoleDisplayItem>{};
  final Map<String, String> _teamByRoleName = <String, String>{};
  final Map<int, String> _skillIconByPlayerNumber = <int, String>{};
  final Map<String, int> _skillUsesLeft = <String, int>{};
  final Set<String> _usedThisPhase = <String>{};
  final Set<int> _previewTargetNumbers = <int>{};
  final Set<int> _protectedPlayerNumbers = <int>{};
  final Set<int> _silencedPlayerNumbers = <int>{};
  int? _lastDoctorProtectedTarget;
  final Map<int, int> _karmaTargetByOwner = <int, int>{};
  int? _myKarmaTargetNumber;
  bool _gameEnded = false;
  bool _resultScreenOpened = false;
  String? _winnerText;
  final Map<int, int> _ghostVoteTargetByVoter = <int, int>{};
  final Map<int, int> _dayVoteTargetByVoter = <int, int>{};
  final List<String> _pendingPhaseAnnouncements = <String>[];
  bool _showNightStartPrompt = false;
  Timer? _nightStartPromptTimer;
  final ScrollController _chatScrollController = ScrollController();
  StreamSubscription<Map<String, dynamic>>? _wsSub;
  bool _showHistoryInMainChat = false;
  SkillOption? _armedSkill;
  /// สกิลสอบสวน: เลือกผู้เล่นคนที่ 1 แล้วรอเลือกคนที่ 2 เพื่อเทียบฝ่าย
  int? _compareInvestigateFirst;

  int myPlayerNumber = 1;
  int? selectedTarget;
  int _activePlayerCount = 16;
  final Map<int, String> _playerIdByNumber = <int, String>{};
  int? _phaseDeadlineAtUnix;
  int _lastPhaseSyncUnix = 0;
  int _lastPhaseAdvanceRequestUnix = 0;
  bool _amHost = false;

  /// 🌞 Day / 🌙 Night
  bool isDay = false;
  bool _lastIsDay = false;
  bool _isDayVoting = false;
  int _phaseSecondsLeft = 20;
  Timer? _phaseTimer;

  bool get _isMyPlayerAlive => _aliveByPlayerNumber[myPlayerNumber] ?? true;
  String get _myCurrentRole =>
      (_roleByPlayerNumber[myPlayerNumber] ?? widget.role ?? '').trim();
  bool get _isMyPlayerGhost => _isGhostRole(_myCurrentRole);
  bool get _isMyPlayerSilencedInDay => isDay && _silencedPlayerNumbers.contains(myPlayerNumber);
  bool get _canSendInCurrentPhase =>
      _isMyPlayerAlive && !_isMyPlayerSilencedInDay && (isDay ? true : _isMyPlayerGhost);
  String get _currentPhase => isDay ? 'day' : 'night';
  String get _chatDisabledReason {
    if (_isMyPlayerSilencedInDay) {
      return 'คุณถูกสาปให้พูดไม่ได้ในช่วงกลางวันนี้';
    }
    if (_isMyPlayerAlive) {
      return 'กลางคืนแชทได้เฉพาะฝ่ายผี';
    }
    return 'ผู้เล่นที่ตายแล้วดูเกมได้อย่างเดียว (โหวต/สกิล/แชทไม่ได้) จนกว่าจะถูกชุบชีวิต';
  }

  List<ChatMessage> get _visibleChatMessages {
    if (isDay) {
      return chatMessages.where((m) => m.phaseType == 'day').toList();
    }
    if (_isMyPlayerAlive && _isMyPlayerGhost) {
      return chatMessages.where((m) => m.phaseType == 'night').toList();
    }
    return <ChatMessage>[];
  }

  List<ChatMessage> get _chatBoxMessages {
    return _showHistoryInMainChat ? _oppositePhaseChatMessages : _visibleChatMessages;
  }

  String get _chatPanelLabel {
    if (!_showHistoryInMainChat) return '';
    return isDay ? 'ประวัติแชทกลางคืน' : 'ประวัติแชทกลางวัน';
  }

  Map<int, String> get _effectiveSkillIcons {
    final merged = <int, String>{..._deadRoleIconByPlayerNumberVisibleToAll};
    merged.addAll(_ghostRoleIconByPlayerNumberForGhostView);
    merged.addAll(_skillIconByPlayerNumber);
    if (_myKarmaTargetNumber != null) {
      merged[_myKarmaTargetNumber!] =
          RoleService.skillImageUrl(GameSkills.karmaSecret);
    }
    if (_armedSkill == null) {
      return merged;
    }
    if (_armedSkill!.name == GameSkills.policeCheck &&
        _compareInvestigateFirst != null) {
      merged[_compareInvestigateFirst!] = _armedSkill!.image;
    }
    for (final n in _previewTargetNumbers) {
      merged.putIfAbsent(n, () => _armedSkill!.image);
    }
    return merged;
  }

  Map<int, String> get _ghostRoleIconByPlayerNumberForGhostView {
    if (!_isMyPlayerGhost) return const <int, String>{};
    final out = <int, String>{};
    for (final p in players) {
      if (!_isActivePlayerNumber(p.number)) continue;
      final roleName = (_roleByPlayerNumber[p.number] ?? '').trim();
      if (!_isGhostRole(roleName)) continue;
      final roleInfo = _roleCatalogByName[RoleService.normalizeKey(roleName)];
      if (roleInfo == null || roleInfo.imagePath.trim().isEmpty) continue;
      out[p.number] = roleInfo.imagePath;
    }
    return out;
  }

  Map<int, String> get _deadRoleIconByPlayerNumberVisibleToAll {
    final out = <int, String>{};
    for (final p in players) {
      if (!_isActivePlayerNumber(p.number)) continue;
      final isAlive = _aliveByPlayerNumber[p.number] ?? true;
      if (isAlive) continue;
      final roleName = (_roleByPlayerNumber[p.number] ?? '').trim();
      final roleInfo = _roleCatalogByName[RoleService.normalizeKey(roleName)];
      if (roleInfo == null || roleInfo.imagePath.trim().isEmpty) continue;
      out[p.number] = roleInfo.imagePath;
    }
    return out;
  }

  List<ChatMessage> get _oppositePhaseChatMessages {
    if (isDay) {
      return chatMessages.where((m) => m.phaseType == 'night').toList();
    }
    return chatMessages.where((m) => m.phaseType == 'day').toList();
  }

  Map<int, int> get _ghostVoteCountByTarget {
    final counts = <int, int>{};
    for (final target in _ghostVoteTargetByVoter.values) {
      if (!_isActivePlayerNumber(target)) continue;
      counts[target] = (counts[target] ?? 0) + 1;
    }
    return counts;
  }

  Map<int, int> get _dayVoteCountByTarget {
    final counts = <int, int>{};
    for (final target in _dayVoteTargetByVoter.values) {
      if (!_isActivePlayerNumber(target)) continue;
      counts[target] = (counts[target] ?? 0) + 1;
    }
    return counts;
  }

  String get _phaseTitle {
    if (_gameEnded) {
      return _winnerText ?? 'เกมจบแล้ว';
    }
    if (isDay) {
      return _isDayVoting
          ? 'ช่วงเวลาโหวต $_phaseSecondsLeft วินาที'
          : 'ประชุมตอนกลางวัน $_phaseSecondsLeft วินาที';
    }
    return 'เวลากลางคืน $_phaseSecondsLeft วินาที';
  }

  void _notify(String message) {
    // Intentionally disabled: user requested no bottom notifications.
  }

  void _showNightStartPromptIfNeeded() {
    if (isDay || !_isMyPlayerGhost || !_isMyPlayerAlive) return;
    _nightStartPromptTimer?.cancel();
    setState(() {
      _showNightStartPrompt = true;
    });
    _nightStartPromptTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      setState(() {
        _showNightStartPrompt = false;
      });
    });
  }

  void _scrollChatToLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_chatScrollController.hasClients) return;
      final max = _chatScrollController.position.maxScrollExtent;
      _chatScrollController.animateTo(
        max,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  void _startPhaseTimer() {
    _phaseTimer?.cancel();
    _phaseTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final deadline = _phaseDeadlineAtUnix;
      if (deadline == null) {
        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        if (now - _lastPhaseSyncUnix >= 2) {
          _lastPhaseSyncUnix = now;
          WsService.instance.syncRoom();
        }
        return;
      }
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final next = (deadline - now).clamp(0, 9999);
      setState(() => _phaseSecondsLeft = next);
      if (next == 0 && now - _lastPhaseSyncUnix >= 1) {
        _lastPhaseSyncUnix = now;
        WsService.instance.syncRoom();
        if (now - _lastPhaseAdvanceRequestUnix >= 2) {
          _lastPhaseAdvanceRequestUnix = now;
          WsService.instance.send('game.advance_phase', {});
        }
      }
    });
  }

  void _applyServerPhase({
    required String phase,
    int? phaseDeadlineAt,
  }) {
    final normalized = phase.toLowerCase();
    final wasDay = isDay;
    setState(() {
      switch (normalized) {
        case 'day':
          isDay = true;
          _isDayVoting = false;
          break;
        case 'voting':
          isDay = true;
          _isDayVoting = true;
          break;
        case 'night':
          isDay = false;
          _isDayVoting = false;
          break;
        case 'end':
          _gameEnded = true;
          break;
      }
      if (phaseDeadlineAt != null) {
        _phaseDeadlineAtUnix = phaseDeadlineAt;
        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        _phaseSecondsLeft = (phaseDeadlineAt - now).clamp(0, 9999);
      }
    });
    if (wasDay != isDay) {
      _syncPhaseSensitiveState();
    }
    _startPhaseTimer();
  }

  /// Merges authoritative `room.state` from the server (roster, optional per-seat
  /// `alive`, `myRole` / `myAlive` for this client). Local animations may update
  /// death UI between polls; the next `room.state` reconciles to server truth.
  void _applyRoomStateFromServer(Map<String, dynamic> payload) {
    final playersJson = payload['players'];
    if (playersJson is List && playersJson.isNotEmpty) {
      final nextActive = playersJson.length.clamp(1, 16);
      final nextPlayers = List<PlayerModel>.generate(
        16,
        (i) => PlayerModel(number: i + 1, name: 'Player${i + 1}'),
        growable: false,
      );
      final nextPlayerIdByNumber = <int, String>{};
      final nextAliveBySeat = <int, bool>{};
      final myUserIdNorm = _normPlayerId(AuthService.currentUser.value?.userId);
      bool nextAmHost = _amHost;
      for (var i = 0; i < playersJson.length; i++) {
        final p = playersJson[i];
        if (p is! Map) continue;
        final number = i + 1;
        if (number > 16) continue;
        final username = (p['username'] as String?)?.trim();
        final rawPid = p['playerId'] ?? p['id'];
        final playerId =
            rawPid == null ? '' : rawPid.toString().trim();
        final isHost = p['isHost'] == true;
        final aliveRaw = p['alive'];
        if (aliveRaw is bool) {
          nextAliveBySeat[number] = aliveRaw;
        }
        nextPlayers[number - 1] = PlayerModel(
          number: number,
          name: (username == null || username.isEmpty) ? 'Player$number' : username,
          playerId: playerId.isEmpty ? null : playerId,
        );
        if (playerId.isNotEmpty) {
          nextPlayerIdByNumber[number] = playerId;
          if (myUserIdNorm.isNotEmpty &&
              _normPlayerId(playerId) == myUserIdNorm) {
            nextAmHost = isHost;
          }
        }
      }
      final nextMyPlayerNumber = _resolveMySeatFromServerData(
        fallback: myPlayerNumber,
        roster: nextPlayers,
        idByNumber: nextPlayerIdByNumber,
        activeCount: nextActive,
      );
      setState(() {
        players = nextPlayers;
        _activePlayerCount = nextActive;
        myPlayerNumber = nextMyPlayerNumber;
        _amHost = nextAmHost;
        _playerIdByNumber
          ..clear()
          ..addAll(nextPlayerIdByNumber);
        for (final e in nextAliveBySeat.entries) {
          _aliveByPlayerNumber[e.key] = e.value;
        }
        final serverRoles = widget.serverRolesByPlayerId;
        if (serverRoles != null && serverRoles.isNotEmpty) {
          for (final entry in nextPlayerIdByNumber.entries) {
            final role = lookupRoleForPlayerId(serverRoles, entry.value);
            if (role != null && role.trim().isNotEmpty) {
              _roleByPlayerNumber[entry.key] = role;
            }
          }
        }
        final myRoleRaw = payload['myRole'];
        if (myRoleRaw is String && myRoleRaw.trim().isNotEmpty) {
          _roleByPlayerNumber[nextMyPlayerNumber] = myRoleRaw.trim();
        }
        final myAliveRaw = payload['myAlive'];
        if (myAliveRaw is bool) {
          _aliveByPlayerNumber[nextMyPlayerNumber] = myAliveRaw;
        }
      });
    }
    final runtime = payload['runtime'];
    if (runtime is Map<String, dynamic>) {
      final phase = runtime['phase'] as String?;
      final deadline = runtime['phaseDeadlineAt'] as int?;
      if (phase != null) {
        _applyServerPhase(phase: phase, phaseDeadlineAt: deadline);
      }
    }
  }

  void _onServerMessage(Map<String, dynamic> msg) {
    final type = msg['type'] as String?;
    if (type == null || !mounted) return;
    switch (type) {
      case 'room.state':
        final payload = msg['payload'] as Map<String, dynamic>?;
        if (payload != null) _applyRoomStateFromServer(payload);
        break;
      case 'game.phase_changed':
        final payload = msg['payload'] as Map<String, dynamic>?;
        if (payload != null) {
          _queuePhaseSummaryFromServerPayload(payload);
          final winnerRaw = payload['winnerKind'] as String?;
          _applyServerPhase(
            phase: (payload['phase'] as String?) ?? 'Night',
            phaseDeadlineAt: payload['phaseDeadlineAt'] as int?,
          );
          if (winnerRaw != null && winnerRaw.isNotEmpty) {
            final winner = _winnerKindFromServer(winnerRaw);
            if (winner != null) {
              _finishGame(
                winnerKind: winner,
                winnerText: switch (winner) {
                  _WinnerKind.villagers => 'ฝ่ายชาวบ้านชนะ',
                  _WinnerKind.ghosts => 'ฝ่ายผีชนะ',
                  _WinnerKind.serialKiller => '${GameRoles.serialKiller}ชนะ',
                  _WinnerKind.spirit => '${GameRoles.karma}ชนะ',
                },
                endAnnouncement: 'เกมจบ',
              );
            }
          }
        }
        break;
      case 'game.chat_message':
        final payload = msg['payload'] as Map<String, dynamic>?;
        if (payload == null) return;
        final senderId = (payload['playerId'] as String?) ?? '';
        final senderName = (payload['username'] as String?) ?? 'ผู้เล่น';
        final text = (payload['text'] as String?) ?? '';
        if (text.trim().isEmpty) return;
        final serverPhase = (payload['phaseType'] as String?)?.toLowerCase().trim();
        final phaseTag = serverPhase == 'night' || serverPhase == 'day'
            ? serverPhase!
            : (isDay ? 'day' : 'night');
        final now = DateTime.now();
        setState(() {
          _showHistoryInMainChat = false;
          chatMessages = [
            ...chatMessages,
            ChatMessage(
              messageId: '${now.microsecondsSinceEpoch}_${chatMessages.length}',
              senderId: senderId,
              senderName: senderName,
              message: text,
              phaseType: phaseTag,
              createdAt: now,
            ),
          ];
        });
        _scrollChatToLatest();
        break;
      case 'game.action_accepted':
        _notify('เซิร์ฟเวอร์ยืนยันการใช้สกิลแล้ว');
        break;
      case 'game.vote_accepted':
        _notify('เซิร์ฟเวอร์ยืนยันการโหวตแล้ว');
        break;
      case 'error':
        final payload = msg['payload'];
        final code = payload is Map ? payload['code'] as String? : null;
        final message = payload is Map ? payload['message'] as String? : null;
        if (code == 'ACTION_REJECTED') {
          _rollbackPendingInteractionUi();
          WsService.instance.syncRoom();
          _notify(message ?? 'เซิร์ฟเวอร์ปฏิเสธคำสั่งสกิล');
          break;
        }
        if (code == 'VOTE_REJECTED') {
          _rollbackLocalVoteSelection();
          WsService.instance.syncRoom();
          _notify(message ?? 'เซิร์ฟเวอร์ปฏิเสธการโหวต');
          break;
        }
        if (code == 'CHAT_REJECTED') {
          _notify(message ?? code ?? 'เกิดข้อผิดพลาดจากเซิร์ฟเวอร์');
        }
        break;
    }
  }

  void _rollbackLocalVoteSelection() {
    if (!mounted) return;
    setState(() {
      _dayVoteTargetByVoter.remove(myPlayerNumber);
      _ghostVoteTargetByVoter.remove(myPlayerNumber);
    });
  }

  void _rollbackPendingInteractionUi() {
    if (!mounted) return;
    setState(() {
      _armedSkill = null;
      _compareInvestigateFirst = null;
      _previewTargetNumbers.clear();
      _ghostVoteTargetByVoter.remove(myPlayerNumber);
    });
  }

  void _queueAnnouncementForNextPhase(String message) {
    _pendingPhaseAnnouncements.add(message);
  }

  void _flushPhaseAnnouncementsToCurrentPhase() {
    if (_pendingPhaseAnnouncements.isEmpty) return;
    final now = DateTime.now();
    setState(() {
      for (final m in _pendingPhaseAnnouncements) {
        chatMessages = [
          ...chatMessages,
          ChatMessage(
            messageId: '${now.microsecondsSinceEpoch}_${chatMessages.length}',
            senderId: '0',
            senderName: 'ระบบ',
            message: m,
            phaseType: isDay ? 'day' : 'night',
            createdAt: now,
          ),
        ];
      }
      _pendingPhaseAnnouncements.clear();
    });
    _scrollChatToLatest();
  }

  String _playerName(int number) {
    final p = players.firstWhere(
      (x) => x.number == number,
      orElse: () => PlayerModel(number: number, name: 'Player$number'),
    );
    return p.name;
  }

  String _playerLabel(int number) => '$number ${_playerName(number)}';

  int? _seatForPlayerId(String rawId) {
    final want = _normPlayerId(rawId);
    if (want.isEmpty) return null;
    for (final e in _playerIdByNumber.entries) {
      if (_normPlayerId(e.value) == want) return e.key;
    }
    return null;
  }

  String _labelForPlayerId(String rawId) {
    final seat = _seatForPlayerId(rawId);
    if (seat != null) return _playerLabel(seat);
    return rawId;
  }

  /// Chat announcements derived from server [game.phase_changed] (no local kill simulation).
  void _queuePhaseSummaryFromServerPayload(Map<String, dynamic> payload) {
    final prev = (payload['previousPhase'] as String?)?.toLowerCase() ?? '';
    final phase = (payload['phase'] as String?)?.toLowerCase() ?? '';

    if (prev == 'night' && (phase == 'day' || phase == 'voting')) {
      final summary = payload['nightActionSummary'];
      if (summary is Map<String, dynamic>) {
        final kills = summary['killTargets'];
        if (kills is List && kills.isNotEmpty) {
          final labels = <String>[];
          for (final id in kills) {
            if (id is String && id.trim().isNotEmpty) {
              labels.add(_labelForPlayerId(id));
            }
          }
          if (labels.isNotEmpty) {
            _queueAnnouncementForNextPhase('สรุปเหตุการณ์เมื่อคืน');
            _queueAnnouncementForNextPhase('ผู้ที่เสียชีวิต: ${labels.join(', ')}');
          } else {
            _queueAnnouncementForNextPhase('เมื่อคืนไม่มีผู้เสียชีวิต');
          }
        } else {
          _queueAnnouncementForNextPhase('เมื่อคืนไม่มีผู้เสียชีวิต');
        }
        final revived = summary['revived'];
        if (revived is List && revived.isNotEmpty) {
          final labels = <String>[];
          for (final id in revived) {
            if (id is String && id.trim().isNotEmpty) {
              labels.add(_labelForPlayerId(id));
            }
          }
          if (labels.isNotEmpty) {
            _queueAnnouncementForNextPhase('ผู้ที่ฟื้นคืนชีพ: ${labels.join(', ')}');
          }
        }
      } else {
        _queueAnnouncementForNextPhase('สรุปเหตุการณ์เมื่อคืน');
        _queueAnnouncementForNextPhase('เมื่อคืนไม่มีผู้เสียชีวิต');
      }
    }

    if (prev == 'voting' && phase == 'night') {
      _queueAnnouncementForNextPhase('สรุปผลการโหวตกลางวัน');
      final elim = payload['eliminatedPlayerId'] as String?;
      if (elim != null && elim.trim().isNotEmpty) {
        _queueAnnouncementForNextPhase('ผู้ที่ถูกโหวตออก: ${_labelForPlayerId(elim)}');
      } else {
        _queueAnnouncementForNextPhase('ไม่มีผู้เล่นถูกโหวตออกในรอบนี้');
      }
      final extra = payload['extraEliminatedPlayerId'] as String?;
      if (extra != null && extra.trim().isNotEmpty) {
        _queueAnnouncementForNextPhase(
          'มีผู้เสียชีวิตเพิ่มเติม: ${_labelForPlayerId(extra)}',
        );
      }
    }
  }

  void _assignKarmaTargetsIfNeeded() {
    for (final p in players) {
      if (!_isActivePlayerNumber(p.number)) continue;
      final role = _roleByPlayerNumber[p.number] ?? '';
      if (role != GameRoles.karma) continue;
      if (_karmaTargetByOwner.containsKey(p.number)) continue;
      final candidates = players
          .map((x) => x.number)
          .where((n) => _isActivePlayerNumber(n) && n != p.number)
          .toList()
        ..sort();
      if (candidates.isNotEmpty) {
        candidates.shuffle();
        final picked = candidates.first;
        _karmaTargetByOwner[p.number] = picked;
        if (p.number == myPlayerNumber) {
          _myKarmaTargetNumber = picked;
        }
      }
    }
  }

  void _finishGame({
    required _WinnerKind winnerKind,
    required String winnerText,
    required String endAnnouncement,
  }) {
    setState(() {
      _gameEnded = true;
      _winnerText = winnerText;
    });
    _queueAnnouncementForNextPhase(endAnnouncement);
    _openResultScreen(winnerKind);
  }

  void _openResultScreen(_WinnerKind winnerKind) {
    if (_resultScreenOpened || !mounted) return;
    _resultScreenOpened = true;
    final myPerspective = _mySidePerspective();
    final isWinForMe = myPerspective == winnerKind;
    final Widget screen = switch (myPerspective) {
      _WinnerKind.villagers =>
        isWinForMe ? const VillagersWinScreen() : const VillagersDefeatScreen(),
      _WinnerKind.ghosts =>
        isWinForMe ? const GhostsWinScreen() : const GhostsDefeatScreen(),
      _WinnerKind.serialKiller => isWinForMe
          ? const SerialKillerWinScreen()
          : const SerialKillerDefeatScreen(),
      _WinnerKind.spirit =>
        isWinForMe ? const SpiritWinScreen() : const SpiritDefeatScreen(),
    };
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => screen),
      );
    });
  }

  _WinnerKind _mySidePerspective() {
    final myRole = (_roleByPlayerNumber[myPlayerNumber] ?? widget.role ?? '').trim();
    if (myRole == GameRoles.karma) return _WinnerKind.spirit;
    if (myRole == GameRoles.serialKiller) return _WinnerKind.serialKiller;
    final team = _teamOfRole(myRole);
    if (team == GameTeams.ghosts) return _WinnerKind.ghosts;
    return _WinnerKind.villagers;
  }

  _WinnerKind? _winnerKindFromServer(String value) {
    switch (value) {
      case 'villagers':
        return _WinnerKind.villagers;
      case 'ghosts':
        return _WinnerKind.ghosts;
      case 'serial_killer':
        return _WinnerKind.serialKiller;
      case 'spirit':
        return _WinnerKind.spirit;
      default:
        return null;
    }
  }

  @override
  void initState() {
    super.initState();

    players = _buildPlayersWithJoinOrderNames(widget.playerNamesInJoinOrder);
    final nameBased = _resolveActivePlayerCount(widget.playerNamesInJoinOrder);
    final poolLen =
        widget.roomRolePool?.where((s) => s.trim().isNotEmpty).length ?? 0;
    // Quick play passes no names (0) but a deck sized to playerCount — match deck,
    // otherwise modulo role assignment repeats ghosts (e.g. two หมอผีดำ).
    _activePlayerCount = nameBased > 0
        ? nameBased.clamp(1, 16)
        : (poolLen > 0 ? poolLen.clamp(1, 16) : 16);
    myPlayerNumber = _resolveMyPlayerNumber(players);

    chatMessages = [];
    // Only seats 1.._activePlayerCount are "in game". Omit empty seats so the
    // grid treats them as neither dead (urn) nor a missing key incorrectly.
    _aliveByPlayerNumber = {
      for (final p in players)
        if (_isActivePlayerNumber(p.number)) p.number: true,
    };
    _roleByPlayerNumber = _buildRoleByPlayerNumber(_activePlayerCount);
    final myAssignedRole = (widget.role ?? '').trim();
    if (myAssignedRole.isNotEmpty) {
      // Keep local player's role aligned with RandomRole result.
      _roleByPlayerNumber[myPlayerNumber] = myAssignedRole;
    }
    _assignKarmaTargetsIfNeeded();
     /// ROLE INFO

    /// ROLE SKILLS (MOCK) - Active for Case 5 (Day + Skills)
    currentRoleSkills = [
      ..._skillsForRole(_myCurrentRole),
    ];
    for (final s in currentRoleSkills) {
      _skillUsesLeft[s.name] = _maxUsesForSkill(s.name);
    }
    _loadRoleCatalog();
    _lastIsDay = isDay;
    _isDayVoting = false;
    _phaseSecondsLeft = 0;
    _wsSub = WsService.instance.stream.listen(_onServerMessage);
    WsService.instance.syncRoom();
    final initialPhase = widget.initialPhase;
    if (initialPhase != null && initialPhase.isNotEmpty) {
      _applyServerPhase(
        phase: initialPhase,
        phaseDeadlineAt: widget.initialPhaseDeadlineAt,
      );
    }
    // Initial screen starts in night by default.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _showNightStartPromptIfNeeded();
      _scrollChatToLatest();
    });
  }

  Future<void> _loadRoleCatalog() async {
    try {
      final roles = await RoleService.fetchRoles();
      if (!mounted) return;
      setState(() {
        _roleCatalogByName
          ..clear()
          ..addEntries(
            roles.map(
              (r) => MapEntry<String, RoleDisplayItem>(
                RoleService.normalizeKey(r.roleName),
                r,
              ),
            ),
          );
        _teamByRoleName
          ..clear()
          ..addEntries(
            roles.map(
              (r) => MapEntry<String, String>(
                RoleService.normalizeKey(r.roleName),
                r.team,
              ),
            ),
          );
      });
    } catch (_) {
      // Keep hardcoded fallback when backend data is unavailable.
    }
  }

  @override
  void dispose() {
    _wsSub?.cancel();
    _nightStartPromptTimer?.cancel();
    _phaseTimer?.cancel();
    _chatScrollController.dispose();
    super.dispose();
  }

  bool _isGhostRole(String? role) {
    final r = (role ?? '').trim();
    if (r.isEmpty) return false;
    return _teamOfRole(r) == GameTeams.ghosts;
  }

  String _normPlayerId(String? id) => (id ?? '').trim().toLowerCase();

  int _resolveMySeatFromServerData({
    required int fallback,
    required List<PlayerModel> roster,
    required Map<int, String> idByNumber,
    required int activeCount,
  }) {
    final myUserId = _normPlayerId(AuthService.currentUser.value?.userId);
    if (myUserId.isNotEmpty) {
      for (final e in idByNumber.entries) {
        if (e.key < 1 || e.key > activeCount) continue;
        if (_normPlayerId(e.value) == myUserId) return e.key;
      }
    }
    final myUsername =
        (AuthService.currentUser.value?.username ?? '').trim().toLowerCase();
    if (myUsername.isNotEmpty) {
      for (final p in roster) {
        if (p.number < 1 || p.number > activeCount) continue;
        if (p.name.trim().toLowerCase() == myUsername) return p.number;
      }
    }
    return fallback;
  }

  List<PlayerModel> _buildPlayersWithJoinOrderNames(List<String>? names) {
    final ordered = names ?? const <String>[];
    return List.generate(16, (i) {
      final idx = i + 1;
      final name = i < ordered.length && ordered[i].trim().isNotEmpty
          ? ordered[i].trim()
          : 'Player$idx';
      return PlayerModel(number: idx, name: name);
    });
  }

  int _resolveMyPlayerNumber(List<PlayerModel> roster) {
    final myUserId = _normPlayerId(AuthService.currentUser.value?.userId);
    if (myUserId.isNotEmpty) {
      for (final p in roster) {
        if (_normPlayerId(p.playerId) == myUserId) return p.number;
      }
    }
    final me = (AuthService.currentUser.value?.username ?? '').trim().toLowerCase();
    if (me.isNotEmpty) {
      for (final p in roster) {
        if (p.name.trim().toLowerCase() == me) return p.number;
      }
    }
    // Fallback to first slot when username is unavailable in roster.
    return roster.isNotEmpty ? roster.first.number : 1;
  }

  int _resolveActivePlayerCount(List<String>? names) {
    final ordered = names ?? const <String>[];
    final count = ordered.where((n) => n.trim().isNotEmpty).length;
    // If caller did not pass roster names yet, keep default behavior.
    return count > 0 ? count.clamp(1, 16) : 16;
  }

  bool _isActivePlayerNumber(int number) {
    return number >= 1 && number <= _activePlayerCount;
  }

  Map<int, String> _buildRoleByPlayerNumber(int playerCount) {
    List<String> deck;
    final fromPool = widget.roomRolePool;
    if (fromPool != null && fromPool.isNotEmpty) {
      deck = List<String>.from(fromPool);
    } else {
      deck = buildBalancedRoleDeck(playerCount);
    }

    deck = _uniqueNonVillagerRolesPadVillagers(deck);

    if (deck.length < playerCount) {
      deck = [
        ...deck,
        ...List<String>.filled(playerCount - deck.length, GameRoles.villager),
      ];
    } else if (deck.length > playerCount) {
      deck = deck.sublist(0, playerCount);
    }

    final map = <int, String>{};
    for (var i = 1; i <= playerCount; i++) {
      map[i] = deck[i - 1];
    }
    return map;
  }

  /// บทที่ไม่ใช่ชาวบ้านซ้ำ (เช่น หมอผีดำสองใบในสำรับผิดพลาด) → ใบที่สองเป็นชาวบ้าน
  List<String> _uniqueNonVillagerRolesPadVillagers(List<String> roles) {
    final seen = <String>{};
    final villagerKey = RoleService.normalizeKey(GameRoles.villager);
    return roles
        .map((raw) {
          final name = raw.trim();
          if (name.isEmpty) return GameRoles.villager;
          final key = RoleService.normalizeKey(name);
          if (key == villagerKey) return name;
          if (seen.contains(key)) return GameRoles.villager;
          seen.add(key);
          return name;
        })
        .toList(growable: false);
  }

  String _teamOfRole(String role) {
    final teamFromCatalog = _teamByRoleName[RoleService.normalizeKey(role)];
    if (teamFromCatalog != null && teamFromCatalog.isNotEmpty) {
      return teamFromCatalog;
    }
    if (GameRoles.ghostTeamRoles.contains(role)) return GameTeams.ghosts;
    if (GameRoles.independentTeamRoles.contains(role)) return GameTeams.independent;
    return GameTeams.villagers;
  }

   /// ===============================================================
  /// PLAYERS POPUP
  /// ===============================================================

  void openPlayersPopup() {

    showDialog(
      context: context,
      barrierColor: Colors.black54,

      builder: (_) {

        return PlayersPopup(
          players: players
              .where((p) => _isActivePlayerNumber(p.number))
              .toList(growable: false),
          myPlayerNumber: myPlayerNumber,
          myAuthUserId: AuthService.currentUser.value?.userId,
          activePlayerCount: _activePlayerCount,
        );
      },
    );
  }

  void _handleRoleInfoTap(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => _GameRolesDialog(
        allowedRoleNames: _allowedRoleNamesForRoom(players.length),
      ),
    );
  }

  Set<String> _allowedRoleNamesForRoom(int playerCount) {
    final fromRoom = widget.roomRolePool;
    if (fromRoom != null && fromRoom.isNotEmpty) {
      return fromRoom.toSet();
    }
    return balancedAllowedRoleNamesForCount(playerCount);
  }


  void onPlayerTap(int number) {
    if (_gameEnded) return;
    if (!_isActivePlayerNumber(number)) return;
    if (!_isMyPlayerAlive) return;
    if (_armedSkill != null) {
      if (_previewTargetNumbers.isNotEmpty &&
          !_previewTargetNumbers.contains(number)) {
        return;
      }
      _useArmedSkillOnTarget(number);
      return;
    }
    if (number == myPlayerNumber) return;

    setState(() {
      if (isDay) {
        if (!_isDayVoting || !_isMyPlayerAlive) return;
        _dayVoteTargetByVoter[myPlayerNumber] = number;
        final targetId = _playerIdByNumber[number];
        if (targetId != null && targetId.isNotEmpty) {
          WsService.instance.send('game.vote', {'targetId': targetId});
        }
      } else {
        if (!_isMyPlayerGhost || !_isMyPlayerAlive) return;
        _ghostVoteTargetByVoter[myPlayerNumber] = number;
        final targetId = _playerIdByNumber[number];
        if (targetId != null && targetId.isNotEmpty) {
          WsService.instance.send('game.submit_action', {
            'actionType': 'kill',
            'targetId': targetId,
          });
        }
      }
    });
  }

  void openSkillDialog() {
    if (_gameEnded) return;
    if (!_isMyPlayerAlive) return;
    if (_myCurrentRole == GameRoles.krasue) {
      _notify('บทนี้เป็นสกิลติดตัว (Passive) ไม่ต้องกดใช้');
      return;
    }
    bool isPassiveSkill(SkillOption s) {
      final name = s.name.trim();
      final desc = s.description.trim();
      return name.contains(GameSkills.karmaSecret) ||
          name.contains('พรางออร่า') ||
          name.contains('หลอกผลตรวจ') ||
          desc.contains('หลอกผลตรวจ') ||
          desc.contains('ผลเป็นออร่าดี') ||
          desc.contains('ผลตรวจออร่าเป็นดี') ||
          desc.contains('ออร่าเป็นดี') ||
          desc.contains('ทำงานอัตโนมัติ') ||
          desc.contains('passive');
    }
    // "สกิลลอบสังหาร" ใช้ผ่านระบบโหวตกลางคืนของฝ่ายผีเท่านั้น (ไม่ใช้ popup สกิล)
    // "สกิลเป้าหมายลับ" ของเจ้ากรรมนายเวรทำงานอัตโนมัติเมื่อเริ่มเกม
    currentRoleSkills = _skillsForRole(_myCurrentRole)
        .where(
          (s) =>
              s.name != GameSkills.ghostKill &&
              !s.description.contains('ร่วมกันฆ่า') &&
              !isPassiveSkill(s),
        )
        .toList(growable: false);
    // Catalog may load after initState; skill names from API can differ from the
    // first seed — missing keys were read as 0 uses and blocked _armSkill.
    for (final s in currentRoleSkills) {
      _skillUsesLeft.putIfAbsent(s.name, () => _maxUsesForSkill(s.name));
    }
    if (currentRoleSkills.isEmpty) {
      _notify('บทบาทนี้ไม่มีสกิลให้ใช้งาน');
      return;
    }

    if (currentRoleSkills.length == 1) {
      final s = currentRoleSkills.first;
      showDialog(
        context: context,
        barrierColor: Colors.black54,
        builder: (_) => SkillPopupSingle(
          skillName: s.name,
          description: s.description,
          image: s.image,
          onUse: () => _armSkill(s),
        ),
      );
      return;
    }

    final s1 = currentRoleSkills[0];
    final s2 = currentRoleSkills[1];
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => SkillPopupChoice(
        skill1Name: s1.name,
        skill1Description: s1.description,
        skill1Image: s1.image,
        skill2Name: s2.name,
        skill2Description: s2.description,
        skill2Image: s2.image,
        onSkill1: () {
          Navigator.pop(context);
          _armSkill(s1);
        },
        onSkill2: () {
          Navigator.pop(context);
          _armSkill(s2);
        },
        onClose: () => Navigator.pop(context),
      ),
    );
  }

  List<SkillOption> _skillsForRole(String? role) {
    final r = (role ?? _myCurrentRole).trim();
    final fromCatalog = _roleCatalogByName[RoleService.normalizeKey(r)];
    if (fromCatalog != null && fromCatalog.skills.isNotEmpty) {
      return fromCatalog.skills
          .map(
            (s) => SkillOption(
              name: s.name,
              description: s.description,
              image: s.imagePath,
            ),
          )
          .toList(growable: false);
    }
    final defaults = RoleService.defaultSkillsForRoleName(r);
    return defaults
        .map(
          (s) => SkillOption(
            name: s.name,
            description: s.description,
            image: s.imagePath,
          ),
        )
        .toList(growable: false);
  }

  void _armSkill(SkillOption skill) {
    if (skill.name == GameSkills.ghostKill || skill.name == GameSkills.karmaSecret) {
      // Ghost team kill + secret target are system-driven (no manual skill usage UI).
      return;
    }
    if (!_isMyPlayerAlive) return;
    _syncPhaseSensitiveState();
    _skillUsesLeft.putIfAbsent(skill.name, () => _maxUsesForSkill(skill.name));
    final rule = _ruleForSkill(skill.name);
    if (rule != null && rule.allowedPhase != _currentPhase) {
      final phaseText = rule.allowedPhase == 'day' ? 'กลางวัน' : 'กลางคืน';
      _notify('สกิลนี้ใช้ได้เฉพาะช่วง$phaseText');
      return;
    }
    if ((_skillUsesLeft[skill.name] ?? 0) <= 0) {
      _notify('สกิลนี้ใช้ครบจำนวนแล้ว');
      return;
    }
    if (rule?.oncePerPhase == true && _usedThisPhase.contains(skill.name)) {
      final phaseText = _currentPhase == 'day' ? 'กลางวัน' : 'กลางคืน';
      _notify('สกิลนี้ใช้ได้ 1 ครั้งต่อ$phaseText');
      return;
    }
    final validTargets = _computeValidTargets(skill.name, rule);
    if (validTargets.isEmpty) {
      _notify('ไม่มีเป้าหมายที่ใช้สกิลได้ในตอนนี้');
      return;
    }
    if (skill.name == GameSkills.policeCheck && validTargets.length < 2) {
      _notify('ต้องมีผู้เล่นอย่างน้อย 2 คนเพื่อเปรียบเทียบฝ่าย');
      return;
    }
    setState(() {
      _armedSkill = skill;
      _compareInvestigateFirst = null;
      _previewTargetNumbers
        ..clear()
        ..addAll(validTargets);
    });
    _notify('เลือกเป้าหมายเพื่อใช้ ${skill.name}');
  }

  void _useArmedSkillOnTarget(int targetNumber) {
    _syncPhaseSensitiveState();
    final skill = _armedSkill;
    if (skill == null) return;
    final rule = _ruleForSkill(skill.name);
    final targetAlive = _aliveByPlayerNumber[targetNumber] ?? true;
    if (rule?.targetMustBeAlive == true && !targetAlive) {
      _notify('สกิลนี้ใช้กับเป้าหมายที่ยังมีชีวิตเท่านั้น');
      return;
    }
    if (rule?.targetMustBeDead == true && targetAlive) {
      _notify('สกิลนี้ใช้กับเป้าหมายที่ตายแล้วเท่านั้น');
      return;
    }
    if (_previewTargetNumbers.isNotEmpty &&
        !_previewTargetNumbers.contains(targetNumber)) {
      return;
    }

    if (skill.name == GameSkills.policeCheck) {
      if (_compareInvestigateFirst == null) {
        setState(() {
          _compareInvestigateFirst = targetNumber;
          _previewTargetNumbers
            ..clear()
            ..addAll(_computeCompareSecondTargets(skill.name, rule));
        });
        return;
      }
      final firstNum = _compareInvestigateFirst!;
      if (firstNum == targetNumber) return;

      final p1 = players.firstWhere(
        (p) => p.number == firstNum,
        orElse: () => PlayerModel(number: firstNum, name: 'Player$firstNum'),
      );
      final p2 = players.firstWhere(
        (p) => p.number == targetNumber,
        orElse: () => PlayerModel(number: targetNumber, name: 'Player$targetNumber'),
      );
      final t1 = _teamOfRole(_roleByPlayerNumber[firstNum] ?? '');
      final t2 = _teamOfRole(_roleByPlayerNumber[targetNumber] ?? '');
      final sameSide = t1 == t2;
      final resultMessage = sameSide
          ? '${p1.number} ${p1.name} และ ${p2.number} ${p2.name}\nอยู่ฝ่ายเดียวกัน (“$t1”)'
          : '${p1.number} ${p1.name} และ ${p2.number} ${p2.name}\nอยู่คนละฝ่าย (“$t1” กับ “$t2”)';

      final left = ((_skillUsesLeft[skill.name] ?? 1) - 1).clamp(0, 999);
      setState(() {
        _skillIconByPlayerNumber[firstNum] = skill.image;
        _skillIconByPlayerNumber[targetNumber] = skill.image;
        if ((_skillUsesLeft[skill.name] ?? 0) > 0) {
          _skillUsesLeft[skill.name] = left;
        }
        if (rule?.oncePerPhase == true) {
          _usedThisPhase.add(skill.name);
        }
        _armedSkill = null;
        _compareInvestigateFirst = null;
        _previewTargetNumbers.clear();
      });
      showDialog(
        context: context,
        barrierColor: Colors.black54,
        builder: (_) => SkillPopupResult(
          skillName: skill.name,
          skillImage: skill.image,
          resultMessage: resultMessage,
        ),
      );
      return;
    }

    final targetId = _playerIdByNumber[targetNumber];
    if (targetId == null || targetId.isEmpty) {
      WsService.instance.syncRoom();
      return;
    }
    final actionType = _toServerActionType(
      skillName: skill.name,
      roleName: _myCurrentRole,
    );
    if (actionType == null) {
      _notify('สกิลนี้ยังไม่ได้เชื่อมกับ backend (${
          skill.name
      })');
      return;
    }
    WsService.instance.send('game.submit_action', {
      'actionType': actionType,
      'targetId': targetId,
    });

    setState(() {
      _armedSkill = null;
      _compareInvestigateFirst = null;
      _previewTargetNumbers.clear();
    });
    _notify('ส่งคำสั่ง ${skill.name} แล้ว รอยืนยันจากเซิร์ฟเวอร์');
  }

  String? _toServerActionType({
    required String skillName,
    required String? roleName,
  }) {
    return RoleService.actionTypeForSkill(
      skillName: skillName,
      roleName: roleName,
    );
  }

  _SkillRule? _ruleForSkill(String skillName) {
    switch (skillName) {
      case GameSkills.seerCheck:
      case GameSkills.policeCheck:
      case GameSkills.auraCheck:
      case GameSkills.doctorProtect:
      case GameSkills.doctorGuard:
      case GameSkills.ghostKill:
      case GameSkills.serialKill:
      case GameSkills.soldierStandIn:
      case GameSkills.darkProtect:
      case GameSkills.darkCurse:
        return const _SkillRule(
          allowedPhase: 'night',
          targetMustBeAlive: true,
          oncePerPhase: true,
        );
      case GameSkills.undertakerReveal:
        return const _SkillRule(
          allowedPhase: 'night',
          targetMustBeDead: true,
          oncePerPhase: true,
        );
      case GameSkills.witchRevive:
        return const _SkillRule(
          allowedPhase: 'night',
          targetMustBeDead: true,
          oncePerPhase: true,
        );
      case GameSkills.witchPoison:
        return const _SkillRule(
          allowedPhase: 'night',
          targetMustBeAlive: true,
          oncePerPhase: false,
        );
      default:
        return null;
    }
  }

  int _maxUsesForSkill(String skillName) {
    switch (skillName) {
      case GameSkills.witchRevive:
      case GameSkills.witchPoison:
        return 1; // ใช้ได้ครั้งเดียวตลอดเกม (V7)
      case GameSkills.soldierStandIn:
        return 999;
      default:
        return 999; // ใช้ได้ทุกคืน
    }
  }

  void _syncPhaseSensitiveState() {
    if (_lastIsDay == isDay) return;
    final wasDay = _lastIsDay;
    _lastIsDay = isDay;
    // Server is authoritative for elimination + winner. Client only updates
    // phase-local UI state and lets `room.state` / `game.phase_changed` drive truth.
    if (wasDay && !isDay) {
      _showNightStartPromptIfNeeded();
    }
    _flushPhaseAnnouncementsToCurrentPhase();
    _usedThisPhase.clear();
    _protectedPlayerNumbers.clear();
    if (!isDay) {
      // Curse effect lasts for one daytime only.
      _silencedPlayerNumbers.clear();
    }
    _previewTargetNumbers.clear();
    _skillIconByPlayerNumber.clear();
    _armedSkill = null;
    _compareInvestigateFirst = null;
    selectedTarget = null;
    _ghostVoteTargetByVoter.clear();
    _dayVoteTargetByVoter.clear();
    _showHistoryInMainChat = false;
  }

  Set<int> _computeCompareSecondTargets(String skillName, _SkillRule? rule) {
    return _computeValidTargets(skillName, rule)
        .where((n) => n != _compareInvestigateFirst)
        .toSet();
  }

  Set<int> _computeValidTargets(String skillName, _SkillRule? rule) {
    if (rule == null) {
      return players
          .map((p) => p.number)
          .where(_isActivePlayerNumber)
          .where((n) => n != myPlayerNumber)
          .toSet();
    }
    final set = <int>{};
    for (final p in players) {
      if (!_isActivePlayerNumber(p.number)) continue;
      if (p.number == myPlayerNumber) continue;
      final alive = _aliveByPlayerNumber[p.number] ?? true;
      if (rule.targetMustBeAlive && !alive) continue;
      if (rule.targetMustBeDead && alive) continue;
      if (skillName == GameSkills.darkProtect) {
        final role = _roleByPlayerNumber[p.number] ?? '';
        if (_teamOfRole(role) != GameTeams.ghosts) continue;
      }
      // Ghost offensive skills: do not mark / target fellow ghost-faction players.
      if (_skillExcludesGhostFactionTargets(skillName)) {
        final targetRole = _roleByPlayerNumber[p.number] ?? '';
        if (_teamOfRole(targetRole) == GameTeams.ghosts) continue;
      }
      set.add(p.number);
    }
    if ((skillName == GameSkills.doctorProtect || skillName == GameSkills.doctorGuard) &&
        _lastDoctorProtectedTarget != null) {
      set.remove(_lastDoctorProtectedTarget);
    }
    return set;
  }

  /// Night skills that must not be aimed at the ghost team (teammates).
  bool _skillExcludesGhostFactionTargets(String skillName) {
    switch (skillName) {
      case GameSkills.ghostKill:
      case GameSkills.darkCurse:
        return true;
      default:
        return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenH = MediaQuery.of(context).size.height;

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
                  isDay
                      ? 'assets/images/DayTimeBg.jpg'
                      : 'assets/images/NightTimeBg.jpg',
                  fit: BoxFit.cover,
                ),
              ),

              /// Main UI
              Positioned.fill(
                child: Column(
                  children: [
                    ValueListenableBuilder<WsConnectionStatus>(
                      valueListenable: WsService.instance.connectionStatus,
                      builder: (context, status, _) {
                        if (status == WsConnectionStatus.connected) {
                          return const SizedBox(height: 4);
                        }
                        final text = switch (status) {
                          WsConnectionStatus.connecting => 'กำลังเชื่อมต่อเซิร์ฟเวอร์...',
                          WsConnectionStatus.reconnecting => 'เน็ตหลุด กำลังเชื่อมต่อใหม่...',
                          WsConnectionStatus.disconnected =>
                            'ขาดการเชื่อมต่อ รอเชื่อมต่อใหม่อัตโนมัติ',
                          WsConnectionStatus.connected => '',
                        };
                        return Container(
                          width: double.infinity,
                          margin: const EdgeInsets.fromLTRB(10, 6, 10, 2),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.55),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white24),
                          ),
                          child: Text(
                            text,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Color(0xFFFFE066),
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        );
                      },
                    ),

                    /// Top Bar
                    GameTopBar(
                      title: _phaseTitle,
                      onExitTap: () {
                        showDialog(
                          context: context,
                          builder: (_) => const ExitGamePopup(),
                        );
                      },
                      onPlayerTap: openPlayersPopup,
                    ),

                    const SizedBox(height: 6),

                    /// Player Grid
                    Expanded(
                      flex: 5,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: isDay
                            ? PlayerGridDay(
                                players: players,
                                myPlayerNumber: myPlayerNumber,
                                myAuthUserId: AuthService.currentUser.value?.userId,
                                dayVoteTargetByVoter: _dayVoteTargetByVoter,
                                dayVoteCountByTarget: _dayVoteCountByTarget,
                                dayVoteEnabled: isDay &&
                                    _isDayVoting &&
                                    _isMyPlayerAlive &&
                                    _armedSkill == null,
                                onPlayerTap: onPlayerTap,
                                skillIconByPlayerNumber: _effectiveSkillIcons,
                                aliveByPlayerNumber: _aliveByPlayerNumber,
                              )
                            : PlayerGridNight(
                                players: players,
                                myPlayerNumber: myPlayerNumber,
                                myAuthUserId: AuthService.currentUser.value?.userId,
                                ghostVoteTargetByVoter: _ghostVoteTargetByVoter,
                                ghostVoteCountByTarget: _ghostVoteCountByTarget,
                                ghostNightKillVoteEnabled: !isDay &&
                                    _isMyPlayerGhost &&
                                    _isMyPlayerAlive &&
                                    _armedSkill == null,
                                onPlayerTap: onPlayerTap,
                                skillIconByPlayerNumber: _effectiveSkillIcons,
                                aliveByPlayerNumber: _aliveByPlayerNumber,
                              ),
                      ),
                    ),

                    const SizedBox(height: 2),

                    /// Chat Box
                    SizedBox(
                      height: 220,
                      child: ChatBox(
                        messages: _chatBoxMessages,
                        scrollController: _chatScrollController,
                        historyLabel: _showHistoryInMainChat ? _chatPanelLabel : null,
                      ),
                    ),

                    const SizedBox(height: 4),

                    /// Chat Input
                    ChatInputRow(
                      onRoleInfoTap: () {
                        _handleRoleInfoTap(context);
                      },
                      onChatTap: () {
                        setState(() {
                          _showHistoryInMainChat = !_showHistoryInMainChat;
                        });
                        _scrollChatToLatest();
                      },
                      onSkillTap: openSkillDialog,
                      canUseSkills: _isMyPlayerAlive,
                      canSend: _canSendInCurrentPhase,
                      disabledHint: _chatDisabledReason,
                      onSend: (message) {
                        if (!_canSendInCurrentPhase) {
                          _notify(_chatDisabledReason);
                          return;
                        }
                        WsService.instance.send('game.chat', {'text': message});
                      },
                    ),

                    const SizedBox(height: 10),
                  ],
                ),
              ),

              /// 🌞 Day Animation
              if (isDay)
                const Positioned.fill(
                  child: IgnorePointer(
                    child: Center(
                      child: DayTimeAnimation(),
                    ),
                  ),
                ),

              /// 🌙 Night Animation
              if (!isDay)
                const Positioned.fill(
                  child: IgnorePointer(
                    child: Center(
                      child: NightTimeAnimation(),
                    ),
                  ),
                ),
              if (_showNightStartPrompt && !isDay && _isMyPlayerGhost)
                IgnorePointer(
                  child: Center(
                    child: Transform.translate(
                      offset: const Offset(0, -98),
                      child: RichText(
                        textAlign: TextAlign.center,
                        text: const TextSpan(
                          style: TextStyle(
                            fontFamily: 'Charmonman',
                            fontSize: 48,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            shadows: [
                              Shadow(color: Colors.black54, blurRadius: 8),
                            ],
                          ),
                          children: [
                            TextSpan(text: 'โหวตฆ่า'),
                            TextSpan(
                              text: 'ผู้เล่น',
                              style: TextStyle(color: Color(0xFFFF3B3B)),
                            ),
                            TextSpan(text: ' 1 คน'),
                          ],
                        ),
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
}

class _GameRolesDialog extends StatefulWidget {
  final Set<String> allowedRoleNames;

  const _GameRolesDialog({required this.allowedRoleNames});

  @override
  State<_GameRolesDialog> createState() => _GameRolesDialogState();
}

class _GameRolesDialogState extends State<_GameRolesDialog> {
  final ScrollController _scrollController = ScrollController();
  late Future<List<RoleDisplayItem>> _rolesFuture;

  @override
  void initState() {
    super.initState();
    _rolesFuture = RoleService.fetchRoles();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Container(
        width: 360,
        height: 580,
        decoration: BoxDecoration(
          color: const Color(0xFFF2F2F2),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Stack(
          children: [
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.black, size: 34),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 14, 18),
              child: Column(
                children: [
                  const SizedBox(height: 2),
                  const Text(
                    'บทบาท',
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      decoration: TextDecoration.underline,
                      decorationColor: Colors.black,
                      decorationThickness: 1.5,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: RawScrollbar(
                      controller: _scrollController,
                      thumbVisibility: true,
                      trackVisibility: true,
                      thickness: 4,
                      radius: const Radius.circular(12),
                      thumbColor: const Color(0xFF4A4A4A),
                      trackColor: const Color(0xFFD1D1D1),
                      trackBorderColor: Colors.transparent,
                      crossAxisMargin: 2,
                      mainAxisMargin: 2,
                      child: SingleChildScrollView(
                        controller: _scrollController,
                        padding: const EdgeInsets.only(right: 10),
                        child: FutureBuilder<List<RoleDisplayItem>>(
                          future: _rolesFuture,
                          builder: (context, snapshot) {
                            if (snapshot.connectionState == ConnectionState.waiting) {
                              return const Padding(
                                padding: EdgeInsets.only(top: 48),
                                child: Center(child: CircularProgressIndicator()),
                              );
                            }
                            if (snapshot.hasError) {
                              return Padding(
                                padding: const EdgeInsets.only(top: 24),
                                child: Text(
                                  'โหลดบทบาทไม่สำเร็จ: ${snapshot.error}',
                                  style: const TextStyle(color: Colors.redAccent),
                                ),
                              );
                            }
                            final all = snapshot.data ?? const <RoleDisplayItem>[];
                            final roles = all
                                .where((r) => widget.allowedRoleNames.contains(r.roleName))
                                .toList(growable: false);
                            if (roles.isEmpty) {
                              return const Padding(
                                padding: EdgeInsets.only(top: 24),
                                child: Text('ยังไม่พบบทบาทสำหรับห้องนี้'),
                              );
                            }
                            return Column(
                              children: roles
                                  .map(
                                    (r) => RoleDropdownCard(
                                      imagePath: r.imagePath,
                                      roleName: r.roleName,
                                      team: r.team,
                                      aura: r.aura,
                                      description: r.description,
                                    ),
                                  )
                                  .toList(growable: false),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SkillRule {
  final String allowedPhase; // day | night
  final bool targetMustBeAlive;
  final bool targetMustBeDead;
  final bool oncePerPhase;

  const _SkillRule({
    required this.allowedPhase,
    this.targetMustBeAlive = false,
    this.targetMustBeDead = false,
    this.oncePerPhase = false,
  });
}

enum _WinnerKind {
  villagers,
  ghosts,
  serialKiller,
  spirit,
}