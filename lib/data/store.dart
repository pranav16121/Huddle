import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;

import 'models.dart';
import 'repository.dart';
import 'stats.dart';

/// A session that was deleted, kept around so it can be restored by "Undo".
typedef DeletedSession = ({Session session, List<AttendanceRecord> records});

/// The single source of truth for the UI.
///
/// All data lives in memory (a coach's whole history is tiny), so reads are
/// instant and synchronous. Every mutation updates memory first, notifies
/// listeners, then writes through to the [Repository] on a serial queue so
/// writes always land in the order they were made — even when the coach is
/// tapping quickly.
class HuddleStore extends ChangeNotifier {
  HuddleStore(this._repo, Snapshot snapshot, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now {
    _ingest(snapshot);
  }

  final Repository _repo;
  final DateTime Function() _clock;

  final _squads = <String, Squad>{};
  final _players = <String, Player>{};
  final _sessions = <String, Session>{};
  final _records = <String, Map<String, AttendanceRecord>>{};
  final _settings = <String, String>{};

  /// Called when a write fails, so the UI can tell the coach.
  void Function(Object error)? onPersistError;

  /// Called with the full data *before* anything is deleted or replaced, so
  /// a safety copy can be kept. Huddle never throws data away without one.
  Future<void> Function(Snapshot before, String reason)? beforeDestructive;

  int _revision = 0;

  /// Increases on every change. Lets backups skip work when nothing changed.
  int get revision => _revision;

  DateTime get now => _clock();
  DateTime get today => dateOnly(_clock());

  void _ingest(Snapshot s) {
    _squads
      ..clear()
      ..addAll({for (final x in s.squads) x.id: x});
    _players
      ..clear()
      ..addAll({for (final x in s.players) x.id: x});
    _sessions
      ..clear()
      ..addAll({for (final x in s.sessions) x.id: x});
    _records.clear();
    for (final r in s.records) {
      _records.putIfAbsent(r.sessionId, () => {})[r.playerId] = r;
    }
    _settings
      ..clear()
      ..addAll(s.settings);
    _invalidate();
  }

  // ---------------------------------------------------------------------------
  // Persistence plumbing
  // ---------------------------------------------------------------------------

  Future<void> _queue = Future.value();

  Future<void> _persist(Future<void> Function() write) {
    final next = _queue.then((_) => write()).catchError((Object e, st) {
      debugPrint('Huddle: failed to save: $e\n$st');
      onPersistError?.call(e);
    });
    _queue = next;
    return next;
  }

  /// Completes once every pending write has reached the database.
  Future<void> flush() => _queue;

  void _changed() {
    _revision++;
    _invalidate();
    notifyListeners();
  }

  /// Queues a safety copy of the current data ahead of a destructive write.
  void _safetyCopy(String reason) {
    final hook = beforeDestructive;
    if (hook == null) return;
    final before = snapshot();
    _queue = _queue.then((_) async {
      try {
        await hook(before, reason);
      } catch (e) {
        debugPrint('Huddle: safety copy failed: $e');
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Derived data (memoised until the next change)
  // ---------------------------------------------------------------------------

  List<Squad>? _squadList;
  List<Player>? _playerList;
  List<Session>? _sessionList;
  Map<String, List<HistoryEntry>>? _history;
  final _tallyCache = <String, Tally>{};
  final _statsCache = <String, PlayerStats>{};

  void _invalidate() {
    _squadList = null;
    _playerList = null;
    _sessionList = null;
    _history = null;
    _tallyCache.clear();
    _statsCache.clear();
  }

  static int _byName(Player a, Player b) =>
      a.name.toLowerCase().compareTo(b.name.toLowerCase());

  static int _newestFirst(Session a, Session b) {
    final byDate = b.date.compareTo(a.date);
    return byDate != 0 ? byDate : b.createdAt.compareTo(a.createdAt);
  }

  /// Every squad, active first, in creation order.
  List<Squad> get allSquads => _squadList ??= (_squads.values.toList()
    ..sort((a, b) {
      if (a.archived != b.archived) return a.archived ? 1 : -1;
      return a.createdAt.compareTo(b.createdAt);
    }));

  List<Squad> get squads => allSquads.where((s) => !s.archived).toList();

  Squad? squad(String id) => _squads[id];

  List<Player> get allPlayers =>
      _playerList ??= (_players.values.toList()..sort(_byName));

  List<Player> get players => allPlayers.where((p) => !p.archived).toList();

  List<Player> get archivedPlayers =>
      allPlayers.where((p) => p.archived).toList();

  Player? player(String id) => _players[id];

  /// Active players in [squadId], sorted by name.
  List<Player> membersOf(String squadId) =>
      players.where((p) => p.squadIds.contains(squadId)).toList();

  /// All sessions, newest first.
  List<Session> get sessions =>
      _sessionList ??= (_sessions.values.toList()..sort(_newestFirst));

  Session? session(String id) => _sessions[id];

  List<Session> sessionsOf(String squadId) =>
      sessions.where((s) => s.squadId == squadId).toList();

  List<Session> sessionsOn(DateTime day, {String? squadId}) => sessions
      .where(
        (s) =>
            isSameDay(s.date, day) && (squadId == null || s.squadId == squadId),
      )
      .toList();

  Map<String, AttendanceRecord> recordsOf(String sessionId) =>
      Map.unmodifiable(_records[sessionId] ?? const {});

  AttendanceStatus? statusOf(String sessionId, String playerId) =>
      _records[sessionId]?[playerId]?.status;

  Tally tallyOf(String sessionId) => _tallyCache.putIfAbsent(
    sessionId,
    () => Tally.of(
      (_records[sessionId] ?? const {}).values.map((r) => r.status),
    ),
  );

  /// A player's history, newest first.
  List<HistoryEntry> historyOf(String playerId) {
    final history = _history ??= () {
      final map = <String, List<HistoryEntry>>{};
      for (final s in sessions) {
        for (final r in (_records[s.id] ?? const {}).values) {
          map.putIfAbsent(r.playerId, () => []).add((session: s, record: r));
        }
      }
      return map;
    }();
    return history[playerId] ?? const [];
  }

  PlayerStats statsOf(String playerId) => _statsCache.putIfAbsent(
    playerId,
    () => computePlayerStats(historyOf(playerId), today: today),
  );

  /// Aggregate stats for sessions on or after [since] (all time if null),
  /// optionally limited to one squad.
  OverviewStats overview({DateTime? since, String? squadId}) {
    final list =
        sessions
            .where(
              (s) =>
                  (squadId == null || s.squadId == squadId) &&
                  (since == null || !s.date.isBefore(since)),
            )
            .toList()
            .reversed
            .toList();
    return OverviewStats(list, {for (final s in list) s.id: tallyOf(s.id)});
  }

  /// The squad the coach most likely wants to take roll call for right now:
  /// one that trains today, hasn't been done yet, and whose start time is
  /// closest to the current time.
  Squad? suggestedSquad() {
    final t = now;
    final candidates = squads.where((s) => s.trainsOn(t)).toList();
    if (candidates.isEmpty) return null;
    final minutesNow = t.hour * 60 + t.minute;
    int score(Squad s) {
      final done = sessionsOn(t, squadId: s.id).isNotEmpty ? 10000 : 0;
      final start = s.startMinutes;
      // Squads whose start time has long passed are less likely.
      final distance = start == null
          ? 600
          : (minutesNow - start).abs() + (minutesNow > start + 120 ? 300 : 0);
      return done + distance;
    }

    candidates.sort((a, b) => score(a).compareTo(score(b)));
    return candidates.first;
  }

  // ---------------------------------------------------------------------------
  // Settings
  // ---------------------------------------------------------------------------

  static const _kCoachName = 'coachName';
  static const _kTheme = 'themeMode';
  static const _kOnboarded = 'onboarded';
  static const _kRollCallTips = 'rollCallTipsSeen';

  String get coachName => _settings[_kCoachName] ?? '';
  bool get onboarded => _settings[_kOnboarded] == 'true';
  bool get rollCallTipSeen => _settings[_kRollCallTips] == 'true';


  ThemeMode get themeMode => switch (_settings[_kTheme]) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };

  void _setSetting(String key, String value) {
    if (_settings[key] == value) return;
    _settings[key] = value;
    _changed();
    _persist(() => _repo.saveSetting(key, value));
  }

  void setCoachName(String name) => _setSetting(_kCoachName, name.trim());
  void setThemeMode(ThemeMode mode) => _setSetting(_kTheme, mode.name);
  void setOnboarded() => _setSetting(_kOnboarded, 'true');
  void markRollCallTipSeen() => _setSetting(_kRollCallTips, 'true');

  // ---------------------------------------------------------------------------
  // Squads
  // ---------------------------------------------------------------------------

  Squad addSquad({
    required String name,
    required int colorIndex,
    Set<int> weekdays = const {},
    int? startMinutes,
  }) {
    final squad = Squad(
      id: newId(),
      name: name.trim(),
      colorIndex: colorIndex,
      weekdays: {...weekdays},
      startMinutes: startMinutes,
      createdAt: now,
    );
    _squads[squad.id] = squad;
    _changed();
    _persist(() => _repo.saveSquad(squad));
    return squad;
  }

  void updateSquad(Squad squad) {
    _squads[squad.id] = squad;
    _changed();
    _persist(() => _repo.saveSquad(squad));
  }

  void setSquadArchived(String id, bool archived) {
    final squad = _squads[id];
    if (squad == null) return;
    updateSquad(squad.copyWith(archived: archived));
  }

  /// Deletes a squad together with its sessions. Players are kept.
  void deleteSquad(String id) {
    if (!_squads.containsKey(id)) return;
    _safetyCopy('delete-squad');
    _squads.remove(id);
    final doomed = _sessions.values.where((s) => s.squadId == id).toList();
    for (final s in doomed) {
      _sessions.remove(s.id);
      _records.remove(s.id);
    }
    for (final p in _players.values.toList()) {
      if (p.squadIds.contains(id)) {
        _players[p.id] = p.copyWith(squadIds: {...p.squadIds}..remove(id));
      }
    }
    _changed();
    _persist(() => _repo.deleteSquad(id)); // cascades in the database
  }

  // ---------------------------------------------------------------------------
  // Players
  // ---------------------------------------------------------------------------

  Player addPlayer({
    required String name,
    Set<String> squadIds = const {},
    String? jersey,
    String notes = '',
  }) {
    final player = Player(
      id: newId(),
      name: name.trim(),
      jersey: _cleanJersey(jersey),
      squadIds: {...squadIds},
      notes: notes.trim(),
      createdAt: now,
    );
    _players[player.id] = player;
    final joined = _joinLiveSessions(player, player.squadIds);
    _changed();
    _persist(() async {
      await _repo.savePlayer(player);
      await _repo.saveRecords(joined);
    });
    return player;
  }

  List<Player> addPlayers(Iterable<String> names, Set<String> squadIds) {
    final added = <Player>[];
    final joined = <AttendanceRecord>[];
    var i = 0;
    for (final raw in names) {
      final name = raw.trim();
      if (name.isEmpty) continue;
      final player = Player(
        id: newId(),
        name: name,
        squadIds: {...squadIds},
        // Keep the paste order stable even within the same microsecond.
        createdAt: now.add(Duration(microseconds: i++)),
      );
      _players[player.id] = player;
      joined.addAll(_joinLiveSessions(player, player.squadIds));
      added.add(player);
    }
    if (added.isEmpty) return added;
    _changed();
    _persist(() async {
      for (final p in added) {
        await _repo.savePlayer(p);
      }
      await _repo.saveRecords(joined);
    });
    return added;
  }

  void updatePlayer(Player updated) {
    final old = _players[updated.id];
    if (old == null) return;
    final cleaned = updated.copyWith(
      name: updated.name.trim(),
      jersey: () => _cleanJersey(updated.jersey),
      notes: updated.notes.trim(),
    );
    _players[cleaned.id] = cleaned;
    final added = cleaned.squadIds.difference(old.squadIds);
    final removed = old.squadIds.difference(cleaned.squadIds);
    final joined = cleaned.archived
        ? <AttendanceRecord>[]
        : _joinLiveSessions(cleaned, added);
    final left = _leaveLiveSessions(cleaned.id, removed);
    _changed();
    _persist(() async {
      await _repo.savePlayer(cleaned);
      await _repo.saveRecords(joined);
      await _repo.deleteRecords(left);
    });
  }

  /// Archived players keep their history but disappear from roll calls.
  void setPlayerArchived(String id, bool archived) {
    final player = _players[id];
    if (player == null || player.archived == archived) return;
    final updated = player.copyWith(archived: archived);
    _players[id] = updated;
    final joined = archived
        ? <AttendanceRecord>[]
        : _joinLiveSessions(updated, updated.squadIds);
    final left = archived
        ? _leaveLiveSessions(id, updated.squadIds)
        : <(String, String)>[];
    _changed();
    _persist(() async {
      await _repo.savePlayer(updated);
      await _repo.saveRecords(joined);
      await _repo.deleteRecords(left);
    });
  }

  /// Permanently deletes a player and their whole attendance history.
  void deletePlayer(String id) {
    if (!_players.containsKey(id)) return;
    _safetyCopy('delete-player');
    _players.remove(id);
    for (final records in _records.values) {
      records.remove(id);
    }
    _changed();
    _persist(() => _repo.deletePlayer(id)); // cascades in the database
  }

  static String? _cleanJersey(String? jersey) {
    final j = jersey?.trim();
    return (j == null || j.isEmpty) ? null : j;
  }

  /// A player who joins a squad mid-day is added (as away) to that squad's
  /// sessions from today onwards, so they show up in the live roll call.
  List<AttendanceRecord> _joinLiveSessions(Player p, Set<String> squadIds) {
    if (squadIds.isEmpty) return const [];
    final created = <AttendanceRecord>[];
    for (final s in _sessions.values) {
      if (!squadIds.contains(s.squadId) || s.date.isBefore(today)) continue;
      final records = _records.putIfAbsent(s.id, () => {});
      if (records.containsKey(p.id)) continue;
      final r = AttendanceRecord(
        sessionId: s.id,
        playerId: p.id,
        status: AttendanceStatus.absent,
        updatedAt: now,
      );
      records[p.id] = r;
      created.add(r);
    }
    return created;
  }

  /// The reverse: leaving a squad (or being archived) drops the player from
  /// today's and future sessions — but only where they weren't marked, so no
  /// real attendance is ever thrown away.
  List<(String, String)> _leaveLiveSessions(
    String playerId,
    Set<String> squadIds,
  ) {
    if (squadIds.isEmpty) return const [];
    final removed = <(String, String)>[];
    for (final s in _sessions.values) {
      if (!squadIds.contains(s.squadId) || s.date.isBefore(today)) continue;
      final records = _records[s.id];
      final r = records?[playerId];
      if (r != null && r.status == AttendanceStatus.absent) {
        records!.remove(playerId);
        removed.add((s.id, playerId));
      }
    }
    return removed;
  }

  // ---------------------------------------------------------------------------
  // Sessions & attendance
  // ---------------------------------------------------------------------------

  /// Creates a session with a record for every player in [statuses].
  Session createSession({
    required String squadId,
    required DateTime date,
    required Map<String, AttendanceStatus> statuses,
  }) {
    final at = now;
    final session = Session(
      id: newId(),
      squadId: squadId,
      date: dateOnly(date),
      createdAt: at,
    );
    _sessions[session.id] = session;
    final records = [
      for (final e in statuses.entries)
        AttendanceRecord(
          sessionId: session.id,
          playerId: e.key,
          status: e.value,
          updatedAt: at,
        ),
    ];
    _records[session.id] = {for (final r in records) r.playerId: r};
    _changed();
    _persist(() => _repo.saveSession(session, records: records));
    return session;
  }

  void setStatus(String sessionId, String playerId, AttendanceStatus status) =>
      setStatuses(sessionId, {playerId: status});

  void setStatuses(String sessionId, Map<String, AttendanceStatus> statuses) {
    if (!_sessions.containsKey(sessionId)) return;
    final records = _records.putIfAbsent(sessionId, () => {});
    final at = now;
    final changed = <AttendanceRecord>[];
    statuses.forEach((playerId, status) {
      if (!_players.containsKey(playerId)) return;
      final old = records[playerId];
      if (old?.status == status) return;
      final r =
          old?.withStatus(status, at) ??
          AttendanceRecord(
            sessionId: sessionId,
            playerId: playerId,
            status: status,
            updatedAt: at,
          );
      records[playerId] = r;
      changed.add(r);
    });
    if (changed.isEmpty) return;
    _changed();
    _persist(() => _repo.saveRecords(changed));
  }

  void removeFromSession(String sessionId, String playerId) {
    if (_records[sessionId]?.remove(playerId) == null) return;
    _changed();
    _persist(() => _repo.deleteRecords([(sessionId, playerId)]));
  }

  void updateSession(Session session) {
    if (!_sessions.containsKey(session.id)) return;
    _sessions[session.id] = session;
    _changed();
    _persist(() => _repo.saveSession(session));
  }

  DeletedSession? deleteSession(String id) {
    if (!_sessions.containsKey(id)) return null;
    _safetyCopy('delete-session');
    final session = _sessions.remove(id)!;
    final records = (_records.remove(id) ?? const {}).values.toList();
    _changed();
    _persist(() => _repo.deleteSession(id));
    return (session: session, records: records);
  }

  void restoreSession(DeletedSession deleted) {
    final s = deleted.session;
    if (!_squads.containsKey(s.squadId)) return;
    _sessions[s.id] = s;
    final records = deleted.records
        .where((r) => _players.containsKey(r.playerId))
        .toList();
    _records[s.id] = {for (final r in records) r.playerId: r};
    _changed();
    _persist(() => _repo.saveSession(s, records: records));
  }

  // ---------------------------------------------------------------------------
  // Whole-database operations
  // ---------------------------------------------------------------------------

  Snapshot snapshot() => Snapshot(
    squads: _squads.values.toList(),
    players: _players.values.toList(),
    sessions: _sessions.values.toList(),
    records: [for (final m in _records.values) ...m.values],
    settings: {..._settings},
  );

  /// Replaces everything with a backup. A safety copy of the current data is
  /// kept first, so a restore can always be undone. Settings in the backup
  /// win over current ones; settings it doesn't mention are kept.
  Future<void> replaceAll(Snapshot snapshot) async {
    _safetyCopy('restore');
    final settings = {..._settings, ...snapshot.settings, _kOnboarded: 'true'};
    final merged = Snapshot(
      squads: snapshot.squads,
      players: snapshot.players,
      sessions: snapshot.sessions,
      records: snapshot.records,
      settings: settings,
    );
    _ingest(merged);
    _revision++;
    notifyListeners();
    await _persist(() => _repo.replaceAll(merged));
  }

  // ---------------------------------------------------------------------------
  // Demo cleanup
  // ---------------------------------------------------------------------------

  static const _kDemo = 'demo';
  static bool _isDemoId(String id) => id.startsWith('demo-');

  /// Whether the sample season (shipped by early versions) still needs
  /// clearing out. Once cleaned up this stays false — unless an old backup
  /// that still contains the demo is restored.
  bool get hasDemoData {
    final flag = _settings[_kDemo];
    if (flag == 'removed') return false;
    return flag == 'true' ||
        _squads.keys.any(_isDemoId) ||
        _players.keys.any(_isDemoId) ||
        _sessions.keys.any(_isDemoId);
  }

  /// Removes the sample season — and only the sample season. Anything the
  /// coach created is kept, including their own sessions and players inside
  /// a demo squad (that squad is then kept too). A safety copy is made first.
  ///
  /// Returns the number of demo players removed.
  Future<int> removeDemoData() async {
    if (!hasDemoData) return 0;
    _safetyCopy('remove-demo');

    final sessions = _sessions.keys.where(_isDemoId).toList();
    for (final id in sessions) {
      _sessions.remove(id);
      _records.remove(id);
    }
    final players = _players.keys.where(_isDemoId).toList();
    for (final id in players) {
      _players.remove(id);
      for (final records in _records.values) {
        records.remove(id);
      }
    }
    // Only drop a demo squad if none of the coach's own data uses it.
    final squads = _squads.keys.where((id) {
      if (!_isDemoId(id)) return false;
      final used =
          _sessions.values.any((s) => s.squadId == id) ||
          _players.values.any((p) => p.squadIds.contains(id));
      return !used;
    }).toList();
    squads.forEach(_squads.remove);
    _settings[_kDemo] = 'removed';
    // Nothing of the coach's own? Then show the friendly setup again.
    final nothingLeft = _squads.isEmpty && _players.isEmpty;
    if (nothingLeft) _settings[_kOnboarded] = 'false';
    _changed();

    await _persist(() async {
      for (final id in sessions) {
        await _repo.deleteSession(id);
      }
      for (final id in players) {
        await _repo.deletePlayer(id);
      }
      for (final id in squads) {
        await _repo.deleteSquad(id);
      }
      await _repo.saveSetting(_kDemo, 'removed');
      if (nothingLeft) await _repo.saveSetting(_kOnboarded, 'false');
    });
    return players.length;
  }
}
