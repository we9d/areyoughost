import 'dart:async';

import 'package:flutter/material.dart';

import 'package:areyoughost/models/mock_models.dart' hide RoleInfo;
import 'package:areyoughost/services/auth_service.dart';
import 'package:areyoughost/services/role_service.dart';
import 'package:areyoughost/services/ws_service.dart';
import 'package:areyoughost/ui/game/dialogs/skill_popup_choice.dart';
import 'package:areyoughost/ui/game/dialogs/player_dead_popup.dart';
import 'package:areyoughost/ui/game/dialogs/skill_popup_result.dart';
import 'package:areyoughost/ui/game/dialogs/skill_popup_single.dart';
import 'package:areyoughost/ui/game/widgets/DayTimeAnimation.dart';
import 'package:areyoughost/ui/game/widgets/NightTimeAnimation.dart';
import 'package:areyoughost/ui/game/widgets/chat_box.dart';
import 'package:areyoughost/ui/game/widgets/chat_input_row.dart';
import 'package:areyoughost/ui/game/widgets/exit_game_popup.dart';
import 'package:areyoughost/ui/game/widgets/game_top_bar.dart';
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

  const GameScreen({
    super.key,
    required this.roomId,
    this.role,
    this.roomRolePool,
    this.playerNamesInJoinOrder,
  });

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  static const String _karmaSkillIconUrl =
      'https://qzmqoksvdgenoxdsrcql.supabase.co/storage/v1/object/public/Skills/Special-secret-target.jpg';
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
  final Map<int, List<_NightKillIntent>> _nightKillIntentsByTarget =
      <int, List<_NightKillIntent>>{};
  int? _pendingNightReviveTarget;
  int? _bodyguardProtectTarget;
  int? _lastDoctorProtectedTarget;
  final Map<int, int> _karmaTargetByOwner = <int, int>{};
  int? _myKarmaTargetNumber;
  int? _lastDayExecutedTargetNumber;
  bool _gameEnded = false;
  bool _resultScreenOpened = false;
  String? _winnerText;
  final Map<int, int> _ghostVoteTargetByVoter = <int, int>{};
  final Map<int, int> _dayVoteTargetByVoter = <int, int>{};
  final List<String> _pendingPhaseAnnouncements = <String>[];
  bool _showNightStartPrompt = false;
  Timer? _nightStartPromptTimer;
  final ScrollController _chatScrollController = ScrollController();
  bool _showHistoryInMainChat = false;
  final Set<int> _deadPopupShownNumbers = <int>{};
  SkillOption? _armedSkill;
  /// สกิลสอบสวน: เลือกผู้เล่นคนที่ 1 แล้วรอเลือกคนที่ 2 เพื่อเทียบฝ่าย
  int? _compareInvestigateFirst;

  int myPlayerNumber = 1;
  int? selectedTarget;
  int _activePlayerCount = 16;

  /// 🌞 Day / 🌙 Night
  bool isDay = false;
  bool _lastIsDay = false;
  bool _isDayVoting = false;
  bool _isNightVoting = false;
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
      merged[_myKarmaTargetNumber!] = _karmaSkillIconUrl;
    }
    if (_armedSkill == null) {
      return merged;
    }
    if (_armedSkill!.name == 'สกิลสอบสวน' && _compareInvestigateFirst != null) {
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
    if (_isMyPlayerGhost) {
      if (_isNightVoting) {
        return 'ช่วงเวลาโหวต $_phaseSecondsLeft วินาที';
      }
      return 'เวลากลางคืน $_phaseSecondsLeft วินาที';
    }
    // Non-ghost players see one continuous night timer (35 -> 1)
    // while internally the phase is split into 20s + 15s voting.
    final visibleNightLeft = _isNightVoting ? _phaseSecondsLeft : _phaseSecondsLeft + 15;
    return 'เวลากลางคืน $visibleNightLeft วินาที';
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
      if (_phaseSecondsLeft <= 1) {
        timer.cancel();
        _advancePhase();
        return;
      }
      setState(() {
        _phaseSecondsLeft -= 1;
      });
    });
  }

  void _advancePhase() {
    if (!mounted) return;
    if (_gameEnded) return;
    if (isDay) {
      if (!_isDayVoting) {
        setState(() {
          _isDayVoting = true;
          _phaseSecondsLeft = 15;
        });
      } else {
        setState(() {
          isDay = false;
          _isDayVoting = false;
          _isNightVoting = false;
          _phaseSecondsLeft = 20;
        });
        _syncPhaseSensitiveState();
      }
    } else {
      if (!_isNightVoting) {
        setState(() {
          _isNightVoting = true;
          _phaseSecondsLeft = 15;
        });
      } else {
        setState(() {
          isDay = true;
          _isNightVoting = false;
          _isDayVoting = false;
          _phaseSecondsLeft = 60;
        });
        _syncPhaseSensitiveState();
      }
    }
    _startPhaseTimer();
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

  _NightResolveSummary _resolveNightPhaseDeterministic() {
    final out = _NightResolveSummary();
    if (_ghostVoteTargetByVoter.isNotEmpty) {
      final counts = _ghostVoteCountByTarget;
      if (counts.isNotEmpty) {
        final top = counts.entries.toList()
          ..sort((a, b) {
            if (b.value != a.value) return b.value.compareTo(a.value);
            return a.key.compareTo(b.key);
          });
        final highest = top.first.value;
        final leaders = top.where((e) => e.value == highest).toList(growable: false);
        if (leaders.length == 1) {
          _queueNightKillIntent(
            targetNumber: leaders.first.key,
            source: _NightKillSource.ghost,
            reasonAnnouncement: '${_playerName(leaders.first.key)} เสียชีวิต เพราะโดนฝ่ายผีฆ่า',
            popupDetail:
                'ผู้เล่นที่ตายจะดูเกมได้อย่างเดียวจนกว่าจะถูกชุบชีวิต (สกิลชุบชีวิตของสัปเหร่อ)',
          );
        } else {
          _queueAnnouncementForNextPhase('โหวตฝ่ายผีเสมอกัน ยังไม่มีผู้เล่นถูกกำจัดในคืนนี้');
        }
      }
    }

    final bodyguardTarget = _bodyguardProtectTarget;
    if (bodyguardTarget != null &&
        _isActivePlayerNumber(bodyguardTarget) &&
        (_aliveByPlayerNumber[myPlayerNumber] ?? false)) {
      final existing = _nightKillIntentsByTarget[bodyguardTarget];
      if (existing != null && existing.isNotEmpty && bodyguardTarget != myPlayerNumber) {
        _nightKillIntentsByTarget.remove(bodyguardTarget);
        for (final intent in existing) {
          _queueNightKillIntent(
            targetNumber: myPlayerNumber,
            source: _NightKillSource.bodyguardSacrifice,
            reasonAnnouncement:
                '${_playerName(myPlayerNumber)} ยืนรับการโจมตีแทน ${_playerName(bodyguardTarget)}',
            popupDetail: 'ทหารสละชีวิตเพื่อปกป้องเป้าหมายในคืนนี้',
          );
          out.protected.add(bodyguardTarget);
          out.logs.add('Bodyguard redirected ${intent.source.name} -> $bodyguardTarget');
        }
      }
    }

    final targets = _nightKillIntentsByTarget.keys.toList()..sort();
    final diedThisNight = <int>{};
    for (final targetNumber in targets) {
      if (!_isActivePlayerNumber(targetNumber)) continue;
      if (!(_aliveByPlayerNumber[targetNumber] ?? true)) continue;
      final intents = List<_NightKillIntent>.from(
        _nightKillIntentsByTarget[targetNumber] ?? const <_NightKillIntent>[],
      );
      if (intents.isEmpty) continue;

      if (_protectedPlayerNumbers.contains(targetNumber)) {
        intents.sort((a, b) => a.source.priority.compareTo(b.source.priority));
        intents.removeAt(0); // deterministic single-source block
        out.protected.add(targetNumber);
      }
      if (intents.isEmpty) continue;

      final role = _roleByPlayerNumber[targetNumber] ?? '';
      final hitByGhost = intents.any((i) => i.source == _NightKillSource.ghost);
      if (role == 'คนดวงซวย' && hitByGhost) {
        _roleByPlayerNumber[targetNumber] = 'ผีปอบ';
        out.transformed.add(targetNumber);
        _queueAnnouncementForNextPhase(
          '${_playerName(targetNumber)} ถูกโจมตี แต่พลังคำสาปเปลี่ยนเป็น “ผีปอบ”',
        );
        continue;
      }

      final selected = intents.first;
      _markPlayerDead(
        targetNumber: targetNumber,
        reasonAnnouncement: selected.reasonAnnouncement,
        popupDetail: selected.popupDetail,
      );
      diedThisNight.add(targetNumber);
      out.deaths.add(targetNumber);
      out.deathReasonByNumber[targetNumber] = selected.reasonAnnouncement;
    }

    final reviveTarget = _pendingNightReviveTarget;
    if (reviveTarget != null && diedThisNight.contains(reviveTarget)) {
      setState(() {
        _aliveByPlayerNumber[reviveTarget] = true;
        _deadPopupShownNumbers.remove(reviveTarget);
      });
      out.deaths.remove(reviveTarget);
      out.revived.add(reviveTarget);
      _queueAnnouncementForNextPhase('${_playerName(reviveTarget)} ฟื้นคืนสภาพกลับมามีชีวิต');
    }

    out.cursed.addAll(_silencedPlayerNumbers);
    return out;
  }

  _DayResolveSummary _resolveDayVoteIfAny() {
    final out = _DayResolveSummary();
    if (_dayVoteTargetByVoter.isEmpty) return out;
    final counts = _dayVoteCountByTarget;
    if (counts.isEmpty) return out;
    final top = counts.entries.toList()
      ..sort((a, b) {
        if (b.value != a.value) return b.value.compareTo(a.value);
        return a.key.compareTo(b.key);
      });
    final highest = top.first.value;
    final leaders = top.where((e) => e.value == highest).toList(growable: false);
    if (leaders.length != 1) {
      return out;
    }
    final targetNumber = leaders.first.key;
    final target = players.firstWhere(
      (p) => p.number == targetNumber,
      orElse: () => PlayerModel(number: targetNumber, name: 'Player$targetNumber'),
    );
    _markPlayerDead(
      targetNumber: targetNumber,
      reasonAnnouncement: '${target.name} ถูกโหวตออกจากที่ประชุมตอนกลางวัน',
      popupDetail: 'ผู้เล่นคนนี้ถูกตัดสินให้ออกจากเกมจากเสียงโหวต',
    );
    out.executed = targetNumber;
    _lastDayExecutedTargetNumber = targetNumber;
    out.executedReason = '${target.name} ถูกโหวตออกจากที่ประชุมตอนกลางวัน';
    final executedRole = _roleByPlayerNumber[targetNumber] ?? '';
    if (executedRole == 'ผีตายโหง') {
      final voters = _dayVoteTargetByVoter.entries
          .where((e) => e.value == targetNumber)
          .map((e) => e.key)
          .where((n) => n != targetNumber && (_aliveByPlayerNumber[n] ?? false))
          .toList()
        ..sort();
      int? revengeTarget;
      if (voters.isNotEmpty) {
        revengeTarget = voters.first;
      } else {
        final fallback = players
            .map((p) => p.number)
            .where((n) =>
                n != targetNumber &&
                _isActivePlayerNumber(n) &&
                (_aliveByPlayerNumber[n] ?? false))
            .toList()
          ..sort();
        if (fallback.isNotEmpty) revengeTarget = fallback.first;
      }
      if (revengeTarget != null) {
        _markPlayerDead(
          targetNumber: revengeTarget,
          reasonAnnouncement:
              '${_playerName(revengeTarget)} เสียชีวิตจากแรงอาฆาตของผีตายโหง',
          popupDetail: 'ผีตายโหงทิ้งคำสาปก่อนตาย ทำให้มีผู้เสียชีวิตเพิ่ม',
        );
        out.extraDeath = revengeTarget;
        out.extraDeathReason =
            '${_playerName(revengeTarget)} เสียชีวิตจากแรงอาฆาตของผีตายโหง';
      }
    }
    return out;
  }

  void _queueNightKillIntent({
    required int targetNumber,
    required _NightKillSource source,
    required String reasonAnnouncement,
    required String popupDetail,
  }) {
    if (!_isActivePlayerNumber(targetNumber)) return;
    _nightKillIntentsByTarget.putIfAbsent(targetNumber, () => <_NightKillIntent>[]).add(
          _NightKillIntent(
            source: source,
            reasonAnnouncement: reasonAnnouncement,
            popupDetail: popupDetail,
          ),
        );
  }

  String _playerName(int number) {
    final p = players.firstWhere(
      (x) => x.number == number,
      orElse: () => PlayerModel(number: number, name: 'Player$number'),
    );
    return p.name;
  }

  String _playerLabel(int number) => '$number ${_playerName(number)}';

  void _announceNightResult(_NightResolveSummary result) {
    final deaths = result.deaths.map(_playerLabel).toList(growable: false);
    final protected = result.protected.map(_playerLabel).toList(growable: false);
    final cursed = result.cursed.map(_playerLabel).toList(growable: false);
    final transformed = result.transformed.map(_playerLabel).toList(growable: false);
    _queueAnnouncementForNextPhase('สรุปเหตุการณ์เมื่อคืน');
    if (deaths.isEmpty) {
      _queueAnnouncementForNextPhase('เมื่อคืนไม่มีผู้เสียชีวิต');
    } else {
      _queueAnnouncementForNextPhase('ผู้ที่เสียชีวิต: ${deaths.join(', ')}');
      for (final number in result.deaths) {
        final reason = result.deathReasonByNumber[number];
        if (reason != null && reason.trim().isNotEmpty) {
          _queueAnnouncementForNextPhase('สาเหตุ: $reason');
        }
      }
    }
    if (protected.isNotEmpty) {
      _queueAnnouncementForNextPhase('ผู้ที่รอดจากการป้องกัน: ${protected.join(', ')}');
    }
    if (cursed.isNotEmpty) {
      _queueAnnouncementForNextPhase('ผู้ที่ถูกคำสาปพูดไม่ได้วันนี้: ${cursed.join(', ')}');
    }
    if (transformed.isNotEmpty) {
      _queueAnnouncementForNextPhase('ผู้ที่ถูกแปลงสถานะ: ${transformed.join(', ')}');
    }
  }

  void _announceDayResult(_DayResolveSummary result) {
    _queueAnnouncementForNextPhase('สรุปผลการโหวตกลางวัน');
    if (result.executed == null) {
      _queueAnnouncementForNextPhase('ไม่มีผู้เล่นถูกโหวตออกในรอบนี้');
    } else {
      _queueAnnouncementForNextPhase('ผู้ที่ถูกโหวตออก: ${_playerLabel(result.executed!)}');
      if (result.executedReason != null && result.executedReason!.trim().isNotEmpty) {
        _queueAnnouncementForNextPhase('สาเหตุ: ${result.executedReason}');
      }
    }
    if (result.extraDeath != null) {
      _queueAnnouncementForNextPhase('มีผู้เสียชีวิตเพิ่มเติม: ${_playerLabel(result.extraDeath!)}');
      if (result.extraDeathReason != null && result.extraDeathReason!.trim().isNotEmpty) {
        _queueAnnouncementForNextPhase('สาเหตุ: ${result.extraDeathReason}');
      }
    }
  }

  void _assignKarmaTargetsIfNeeded() {
    for (final p in players) {
      if (!_isActivePlayerNumber(p.number)) continue;
      final role = _roleByPlayerNumber[p.number] ?? '';
      if (role != 'เจ้ากรรมนายเวร') continue;
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

  bool _checkWinConditionAndAnnounce() {
    if (_gameEnded) return true;

    for (final e in _karmaTargetByOwner.entries) {
      final owner = e.key;
      final target = e.value;
      if (_lastDayExecutedTargetNumber == target) {
        final ownerName = _playerName(owner);
        _finishGame(
          winnerKind: _WinnerKind.spirit,
          winnerText: 'เจ้ากรรมนายเวรชนะ',
          endAnnouncement:
              'เกมจบ: $ownerName ทำเงื่อนไขสำเร็จ (เป้าหมายถูกโหวตออกตอนกลางวัน)',
        );
        return true;
      }
    }

    final living = players
        .where((p) => _isActivePlayerNumber(p.number))
        .where((p) => _aliveByPlayerNumber[p.number] ?? false)
        .toList(growable: false);
    if (living.length == 1) {
      final role = _roleByPlayerNumber[living.first.number] ?? '';
      if (role == 'ฆาตกรต่อเนื่อง') {
        _finishGame(
          winnerKind: _WinnerKind.serialKiller,
          winnerText: 'ฆาตกรต่อเนื่องชนะ',
          endAnnouncement: 'เกมจบ: ฆาตกรต่อเนื่องเหลือรอดคนสุดท้าย',
        );
        return true;
      }
    }

    var ghosts = 0;
    var villagers = 0;
    for (final p in living) {
      final team = _teamOfRole(_roleByPlayerNumber[p.number] ?? '');
      if (team == 'ผี') {
        ghosts += 1;
      } else if (team == 'ชาวบ้าน') {
        villagers += 1;
      }
    }
    if (ghosts == 0) {
      _finishGame(
        winnerKind: _WinnerKind.villagers,
        winnerText: 'ฝ่ายชาวบ้านชนะ',
        endAnnouncement: 'เกมจบ: ฝ่ายชาวบ้านกำจัดผีทั้งหมดได้สำเร็จ',
      );
      return true;
    }
    if (ghosts >= villagers) {
      _finishGame(
        winnerKind: _WinnerKind.ghosts,
        winnerText: 'ฝ่ายผีชนะ',
        endAnnouncement: 'เกมจบ: จำนวนผีเท่ากับหรือมากกว่าฝ่ายชาวบ้าน',
      );
      return true;
    }
    return false;
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
    if (myRole == 'เจ้ากรรมนายเวร') return _WinnerKind.spirit;
    if (myRole == 'ฆาตกรต่อเนื่อง') return _WinnerKind.serialKiller;
    final team = _teamOfRole(myRole);
    if (team == 'ผี') return _WinnerKind.ghosts;
    return _WinnerKind.villagers;
  }

  void _markPlayerDead({
    required int targetNumber,
    required String reasonAnnouncement,
    required String popupDetail,
  }) {
    if (!_isActivePlayerNumber(targetNumber)) return;
    final target = players.firstWhere(
      (p) => p.number == targetNumber,
      orElse: () => PlayerModel(number: targetNumber, name: 'Player$targetNumber'),
    );
    final alreadyDead = !(_aliveByPlayerNumber[targetNumber] ?? true);
    if (!alreadyDead) {
      setState(() {
        _aliveByPlayerNumber[targetNumber] = false;
        if (targetNumber == myPlayerNumber) {
          _armedSkill = null;
          _previewTargetNumbers.clear();
          _compareInvestigateFirst = null;
        }
      });
    }
    if (alreadyDead || _deadPopupShownNumbers.contains(targetNumber)) return;
    // Death popup is only for the eliminated player on this device.
    if (targetNumber != myPlayerNumber) return;
    _deadPopupShownNumbers.add(targetNumber);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showDialog<void>(
        context: context,
        barrierColor: Colors.black54,
        builder: (_) => PlayerDeadPopup(
          victimLabel: '${target.number} ${target.name}',
          detailMessage: popupDetail,
          imagePath: 'assets/images/player_dead_urn.png',
        ),
      );
    });
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
    _isNightVoting = false;
    _phaseSecondsLeft = 20;
    _startPhaseTimer();
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
    _nightStartPromptTimer?.cancel();
    _phaseTimer?.cancel();
    _chatScrollController.dispose();
    super.dispose();
  }

  bool _isGhostRole(String? role) {
    final r = (role ?? '').trim();
    if (r.isEmpty) return false;
    final team = _teamByRoleName[RoleService.normalizeKey(r)];
    if (team != null) return team == 'ผี';
    const ghostRoles = <String>{
      'ผีปอบ',
      'ผีกระสือใหญ่',
      'ผีตายโหง',
      'ผีเปรต',
      'หมอผีดำ',
    };
    return ghostRoles.contains(r);
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
    final me = (AuthService.currentUser.value?.username ?? '').trim();
    if (me.isNotEmpty) {
      for (final p in roster) {
        if (p.name.trim() == me) return p.number;
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
        ...List<String>.filled(playerCount - deck.length, 'ชาวบ้าน'),
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
    final villagerKey = RoleService.normalizeKey('ชาวบ้าน');
    return roles
        .map((raw) {
          final name = raw.trim();
          if (name.isEmpty) return 'ชาวบ้าน';
          final key = RoleService.normalizeKey(name);
          if (key == villagerKey) return name;
          if (seen.contains(key)) return 'ชาวบ้าน';
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
    const ghostTeam = <String>{
      'ผีปอบ',
      'ผีกระสือใหญ่',
      'ผีตายโหง',
      'ผีเปรต',
      'หมอผีดำ',
    };
    const neutralTeam = <String>{'เจ้ากรรมนายเวร', 'ฆาตกรต่อเนื่อง'};
    if (ghostTeam.contains(role)) return 'ผี';
    if (neutralTeam.contains(role)) return 'อิสระ';
    return 'ชาวบ้าน';
  }

  String _auraOfRole(String role) {
    final team = _teamOfRole(role);
    if (team == 'ผี') return 'ออร่าดำ';
    if (team == 'อิสระ') return 'ออร่าหม่น';
    return 'ออร่าขาว';
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
              .map((p) => "ห้อง${p.number} ${p.name}")
              .toList(growable: false),
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

    final count = playerCount.clamp(2, 16);
    final evilCount = switch (count) {
      <= 4 => 1,
      <= 7 => 2,
      <= 10 => 3,
      <= 13 => 4,
      _ => 5,
    };
    final neutralCount = count >= 11 ? 2 : (count >= 6 ? 1 : 0);
    final goodCount = (count - evilCount - neutralCount).clamp(1, count);

    const goodCycle = <String>[
      'ชาวบ้าน',
      'ร่างทรง',
      'แพทย์',
      'ทหาร',
      'ตำรวจ',
      'พระธุดงค์',
      'หมอผีคุณไสย',
      'สัปเหร่อ',
    ];
    const evilCycle = <String>[
      'ผีปอบ',
      'ผีกระสือใหญ่',
      'ผีตายโหง',
      'ผีเปรต',
      'หมอผีดำ',
      'ฆาตกรต่อเนื่อง',
    ];
    const neutralCycle = <String>[
      'คนดวงซวย',
      'เจ้ากรรมนายเวร',
    ];

    final allowed = <String>{};
    for (var i = 0; i < goodCount; i++) {
      allowed.add(goodCycle[i % goodCycle.length]);
    }
    for (var i = 0; i < evilCount; i++) {
      allowed.add(evilCycle[i % evilCycle.length]);
    }
    for (var i = 0; i < neutralCount; i++) {
      allowed.add(neutralCycle[i % neutralCycle.length]);
    }
    return allowed;
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
      } else {
        if (!_isNightVoting || !_isMyPlayerGhost || !_isMyPlayerAlive) return;
        _ghostVoteTargetByVoter[myPlayerNumber] = number;
      }
    });
  }

  void openSkillDialog() {
    if (_gameEnded) return;
    if (!_isMyPlayerAlive) return;
    if (_myCurrentRole == 'ผีกระสือใหญ่') {
      _notify('บทนี้เป็นสกิลติดตัว (Passive) ไม่ต้องกดใช้');
      return;
    }
    bool isPassiveSkill(SkillOption s) {
      final name = s.name.trim();
      final desc = s.description.trim();
      return name.contains('สกิลเป้าหมายลับ') ||
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
              s.name != 'สกิลลอบสังหาร' &&
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
    switch (r) {
      case 'ร่างทรง':
        return [
          SkillOption(
            name: 'สกิลตาวิเศษ',
            description: 'เลือกผู้เล่น 1 คน เพื่อทำการตรวจฝ่าย',
            image:
                'https://qzmqoksvdgenoxdsrcql.supabase.co/storage/v1/object/public/Skills/Villager-Clairvoyance-Skill.jpg',
          ),
        ];
      case 'แพทย์':
        return [
          SkillOption(
            name: 'สกิลปกป้อง',
            description: 'ปกป้องผู้เล่น 1 คนในคืนนี้',
            image:
                'https://qzmqoksvdgenoxdsrcql.supabase.co/storage/v1/object/public/Skills/Villager-Defense-Skill.jpg',
          ),
        ];
      case 'ทหาร':
        return [
          SkillOption(
            name: 'สกิลยืนแทน',
            description: 'เลือกผู้เล่น 1 คน ถ้าคืนนั้นโดนฆ่า ทหารจะตายแทน',
            image:
                'https://qzmqoksvdgenoxdsrcql.supabase.co/storage/v1/object/public/Skills/Villager-Defense-Skill.jpg',
          ),
        ];
      case 'ตำรวจ':
        return [
          SkillOption(
            name: 'สกิลสอบสวน',
            description: 'เลือกผู้เล่น 2 คน เพื่อดูว่าอยู่ฝ่ายเดียวกันไหม',
            image:
                'https://qzmqoksvdgenoxdsrcql.supabase.co/storage/v1/object/public/Skills/Villager-Investigation-Skill.jpg',
          ),
        ];
      case 'พระธุดงค์':
        return [
          SkillOption(
            name: 'สกิลตรวจออร่า',
            description: 'ตรวจออร่าผู้เล่น 1 คน',
            image:
                'https://qzmqoksvdgenoxdsrcql.supabase.co/storage/v1/object/public/Skills/Villager-Aura-Skill.jpg',
          ),
        ];
      case 'หมอผีคุณไสย':
        return [
          SkillOption(
            name: 'สกิลชุบชีวิต',
            description: 'ชุบชีวิตผู้เล่นที่ถูกฆ่าในคืนนี้ (ใช้ได้ 1 ครั้ง)',
            image:
                'https://qzmqoksvdgenoxdsrcql.supabase.co/storage/v1/object/public/Skills/Villager-Resurrection-Skill.jpg',
          ),
          SkillOption(
            name: 'สกิลคุณไสยฆ่า',
            description: 'ฆ่าผู้เล่น 1 คน (ใช้ได้ 1 ครั้ง)',
            image:
                'https://qzmqoksvdgenoxdsrcql.supabase.co/storage/v1/object/public/Skills/Villager-Voodoo-Skill.jpg',
          ),
        ];
      case 'สัปเหร่อ':
        return [
          SkillOption(
            name: 'สกิลเปิดบทผู้ตาย',
            description: 'ดูบทบาทผู้ตายได้ 1 คนต่อคืน',
            image:
                'https://qzmqoksvdgenoxdsrcql.supabase.co/storage/v1/object/public/Skills/Villager-Undertaker-Skill.jpg',
          ),
        ];
      case 'ผีปอบ':
      case 'ผีกระสือใหญ่':
      case 'ผีเปรต':
        return const <SkillOption>[];
      case 'ผีตายโหง':
        return [
          SkillOption(
            name: 'สกิลตายโหง',
            description: 'หากถูกโหวตตายตอนกลางวัน เลือกผู้เล่น 1 คนตายตามทันที',
            image:
                'https://qzmqoksvdgenoxdsrcql.supabase.co/storage/v1/object/public/Skills/Ghost-violent-death-skill.jpg',
          ),
        ];
      case 'หมอผีดำ':
        return [
          SkillOption(
            name: 'สกิลปกป้องผี',
            description: 'ปกป้องผี 1 ตัวในคืนนี้',
            image:
                'https://qzmqoksvdgenoxdsrcql.supabase.co/storage/v1/object/public/Skills/Ghost-Protection-Skill.jpg',
          ),
          SkillOption(
            name: 'สกิลสาปพูดไม่ได้',
            description: 'สาปผู้เล่น 1 คนให้พูดไม่ได้ตอนกลางวัน',
            image:
                'https://qzmqoksvdgenoxdsrcql.supabase.co/storage/v1/object/public/Skills/Ghost-curse-skill.jpg',
          ),
        ];
      case 'คนดวงซวย':
        return [
          SkillOption(
            name: 'สกิลคนดวงซวย',
            description: 'หากถูกผีโจมตีครั้งแรก จะไม่ตายและเปลี่ยนเป็นผีปอบทันที',
            image:
                'https://qzmqoksvdgenoxdsrcql.supabase.co/storage/v1/object/public/Skills/Ghost-Jinx-Skill.jpg',
          ),
        ];
      case 'ฆาตกรต่อเนื่อง':
        return [
          SkillOption(
            name: 'สกิลฆ่าเดี่ยว',
            description: 'เลือกผู้เล่น 1 คน เพื่อกำจัดในคืนนี้',
            image:
                'https://qzmqoksvdgenoxdsrcql.supabase.co/storage/v1/object/public/Skills/Special-assassin-skill%27.jpg',
          ),
        ];
      default:
        return const <SkillOption>[];
    }
  }

  void _armSkill(SkillOption skill) {
    if (skill.name == 'สกิลลอบสังหาร' || skill.name == 'สกิลเป้าหมายลับ') {
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
    if (skill.name == 'สกิลสอบสวน' && validTargets.length < 2) {
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

    if (skill.name == 'สกิลสอบสวน') {
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

    final target = players.firstWhere(
      (p) => p.number == targetNumber,
      orElse: () => PlayerModel(number: targetNumber, name: 'Player$targetNumber'),
    );
    final left = ((_skillUsesLeft[skill.name] ?? 1) - 1).clamp(0, 999);
    late String resultMessage;
    setState(() {
      _skillIconByPlayerNumber[targetNumber] = skill.image;
      resultMessage = _buildSkillResultMessage(
        skillName: skill.name,
        target: target,
      );
      if ((_skillUsesLeft[skill.name] ?? 0) > 0) {
        _skillUsesLeft[skill.name] = left;
      }
      if (rule?.oncePerPhase == true) {
        _usedThisPhase.add(skill.name);
      }
      _armedSkill = null;
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
  }

  String _buildSkillResultMessage({
    required String skillName,
    required PlayerModel target,
  }) {
    final targetRole = _roleByPlayerNumber[target.number] ?? 'ไม่ทราบบทบาท';
    final targetTeam = _teamOfRole(targetRole);
    final targetAura = _auraOfRole(targetRole);

    switch (skillName) {
      case 'สกิลตาวิเศษ':
        return '${target.number} ${target.name}\nอยู่ฝ่าย “$targetTeam”';
      case 'สกิลตรวจออร่า':
        return '${target.number} ${target.name}\nตรวจพบ “$targetAura”';
      case 'สกิลเปิดบทผู้ตาย':
        return '${target.number} ${target.name}\nบทบาทคือ “$targetRole”';
      case 'สกิลปกป้อง':
      case 'สกิลคุ้มครอง':
      case 'สกิลปกป้องผี':
        _protectedPlayerNumbers.add(target.number);
        if (skillName == 'สกิลปกป้อง' || skillName == 'สกิลคุ้มครอง') {
          _lastDoctorProtectedTarget = target.number;
        }
        return '${target.number} ${target.name}\nได้รับสถานะ “ป้องกัน” คืนนี้';
      case 'สกิลยืนแทน':
        _bodyguardProtectTarget = target.number;
        return '${target.number} ${target.name}\nถูกเลือกให้ทหารคุ้มกันแทนคืนนี้';
      case 'สกิลสาปพูดไม่ได้':
        _silencedPlayerNumbers.add(target.number);
        _queueAnnouncementForNextPhase(
          '${target.name} ถูกคำสาปให้พูดไม่ได้ในช่วงกลางวัน',
        );
        return '${target.number} ${target.name}\nได้รับสถานะ “พูดไม่ได้” ในกลางวันถัดไป';
      case 'สกิลชุบชีวิต':
        _pendingNightReviveTarget = target.number;
        return '${target.number} ${target.name}\nถูกเลือกเป็นเป้าชุบชีวิตคืนนี้';
      case 'สกิลลอบสังหาร':
      case 'สกิลฆ่าเดี่ยว':
      case 'สกิลคุณไสยฆ่า':
        if (skillName == 'สกิลลอบสังหาร') {
          return '${target.number} ${target.name}\nการฆ่าร่วมของฝ่ายผีใช้ผ่านระบบโหวตกลางคืน';
        } else if (skillName == 'สกิลคุณไสยฆ่า') {
          _queueNightKillIntent(
            targetNumber: target.number,
            source: _NightKillSource.witchKill,
            reasonAnnouncement: '${target.name} เสียชีวิต เพราะโดนคุณไสยเล่นงาน',
            popupDetail: 'ผู้เล่นคนนี้เสียชีวิตจากพลังคุณไสย',
          );
        } else if (skillName == 'สกิลฆ่าเดี่ยว') {
          _queueNightKillIntent(
            targetNumber: target.number,
            source: _NightKillSource.serialKiller,
            reasonAnnouncement: '${target.name} เสียชีวิต เพราะถูกลอบสังหารในตอนกลางคืน',
            popupDetail: 'ผู้เล่นคนนี้ถูกลอบสังหารและออกจากเกม',
          );
        } else {
          _queueNightKillIntent(
            targetNumber: target.number,
            source: _NightKillSource.ghost,
            reasonAnnouncement: '${target.name} เสียชีวิต เพราะโดนฝ่ายผีฆ่า',
            popupDetail: 'ผู้เล่นคนนี้ถูกฝ่ายผีกำจัด',
          );
        }
        return '${target.number} ${target.name}\nถูกหมายเป็นเป้าหมายคืนนี้';
      default:
        return '${target.number} ${target.name}\nใช้ $skillName สำเร็จ';
    }
  }

  _SkillRule? _ruleForSkill(String skillName) {
    switch (skillName) {
      case 'สกิลตาวิเศษ':
      case 'สกิลสอบสวน':
      case 'สกิลตรวจออร่า':
      case 'สกิลปกป้อง':
      case 'สกิลคุ้มครอง':
      case 'สกิลลอบสังหาร':
      case 'สกิลฆ่าเดี่ยว':
      case 'สกิลยืนแทน':
      case 'สกิลปกป้องผี':
      case 'สกิลสาปพูดไม่ได้':
        return const _SkillRule(
          allowedPhase: 'night',
          targetMustBeAlive: true,
          oncePerPhase: true,
        );
      case 'สกิลเปิดบทผู้ตาย':
        return const _SkillRule(
          allowedPhase: 'night',
          targetMustBeDead: true,
          oncePerPhase: true,
        );
      case 'สกิลชุบชีวิต':
        return const _SkillRule(
          allowedPhase: 'night',
          targetMustBeDead: true,
          oncePerPhase: true,
        );
      case 'สกิลคุณไสยฆ่า':
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
      case 'สกิลชุบชีวิต':
      case 'สกิลคุณไสยฆ่า':
        return 1; // ใช้ได้ครั้งเดียวตลอดเกม (V7)
      case 'สกิลยืนแทน':
        return 999;
      default:
        return 999; // ใช้ได้ทุกคืน
    }
  }

  void _syncPhaseSensitiveState() {
    if (_lastIsDay == isDay) return;
    final wasDay = _lastIsDay;
    _lastIsDay = isDay;
    // Night -> Day: deterministic night resolve then show report in day feed.
    if (!wasDay && isDay) {
      final nightResult = _resolveNightPhaseDeterministic();
      _announceNightResult(nightResult);
      _checkWinConditionAndAnnounce();
    }
    // Day -> Night: resolve execute result, then show prompt for ghost players.
    if (wasDay && !isDay) {
      final dayResult = _resolveDayVoteIfAny();
      _announceDayResult(dayResult);
      _checkWinConditionAndAnnounce();
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
    _bodyguardProtectTarget = null;
    _nightKillIntentsByTarget.clear();
    _pendingNightReviveTarget = null;
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
      if (skillName == 'สกิลปกป้องผี') {
        final role = _roleByPlayerNumber[p.number] ?? '';
        if (_teamOfRole(role) != 'ผี') continue;
      }
      // Ghost offensive skills: do not mark / target fellow ghost-faction players.
      if (_skillExcludesGhostFactionTargets(skillName)) {
        final targetRole = _roleByPlayerNumber[p.number] ?? '';
        if (_teamOfRole(targetRole) == 'ผี') continue;
      }
      set.add(p.number);
    }
    if ((skillName == 'สกิลปกป้อง' || skillName == 'สกิลคุ้มครอง') &&
        _lastDoctorProtectedTarget != null) {
      set.remove(_lastDoctorProtectedTarget);
    }
    return set;
  }

  /// Night skills that must not be aimed at the ghost team (teammates).
  bool _skillExcludesGhostFactionTargets(String skillName) {
    switch (skillName) {
      case 'สกิลลอบสังหาร':
      case 'สกิลสาปพูดไม่ได้':
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
                                ghostVoteTargetByVoter: _ghostVoteTargetByVoter,
                                ghostVoteCountByTarget: _ghostVoteCountByTarget,
                                ghostNightKillVoteEnabled: !isDay &&
                                    _isNightVoting &&
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
                        final now = DateTime.now();
                        setState(() {
                          _showHistoryInMainChat = false;
                          chatMessages = [
                            ...chatMessages,
                            ChatMessage(
                              messageId: now.microsecondsSinceEpoch.toString(),
                              // senderId is fixed join-order number in room.
                              senderId: myPlayerNumber.toString(),
                              senderName: players
                                  .firstWhere(
                                    (p) => p.number == myPlayerNumber,
                                    orElse: () => PlayerModel(
                                      number: myPlayerNumber,
                                      name: 'Player$myPlayerNumber',
                                    ),
                                  )
                                  .name,
                              message: message,
                              phaseType: isDay ? 'day' : 'night',
                              createdAt: now,
                            ),
                          ];
                        });
                        _scrollChatToLatest();
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

class _NightKillIntent {
  final _NightKillSource source;
  final String reasonAnnouncement;
  final String popupDetail;

  const _NightKillIntent({
    required this.source,
    required this.reasonAnnouncement,
    required this.popupDetail,
  });
}

enum _NightKillSource {
  ghost(0),
  serialKiller(1),
  witchKill(2),
  bodyguardSacrifice(3);

  const _NightKillSource(this.priority);
  final int priority;
}

class _NightResolveSummary {
  final List<int> deaths = <int>[];
  final Map<int, String> deathReasonByNumber = <int, String>{};
  final List<int> protected = <int>[];
  final List<int> cursed = <int>[];
  final List<int> transformed = <int>[];
  final List<int> revived = <int>[];
  final List<String> logs = <String>[];
}

class _DayResolveSummary {
  int? executed;
  String? executedReason;
  int? extraDeath;
  String? extraDeathReason;
}

enum _WinnerKind {
  villagers,
  ghosts,
  serialKiller,
  spirit,
}