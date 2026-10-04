import 'package:attendance/data/models.dart';
import 'package:attendance/data/repository.dart';

/// A [Repository] that keeps everything in memory, for fast tests.
class MemoryRepository implements Repository {
  MemoryRepository([Snapshot? initial]) {
    if (initial != null) _apply(initial);
  }

  final squads = <String, Squad>{};
  final players = <String, Player>{};
  final sessions = <String, Session>{};
  final records = <(String, String), AttendanceRecord>{};
  final settings = <String, String>{};
  int writes = 0;

  void _apply(Snapshot s) {
    squads
      ..clear()
      ..addAll({for (final x in s.squads) x.id: x});
    players
      ..clear()
      ..addAll({for (final x in s.players) x.id: x});
    sessions
      ..clear()
      ..addAll({for (final x in s.sessions) x.id: x});
    records
      ..clear()
      ..addAll({for (final r in s.records) (r.sessionId, r.playerId): r});
    settings
      ..clear()
      ..addAll(s.settings);
  }

  @override
  Future<Snapshot> load() async => Snapshot(
    squads: squads.values.toList(),
    players: players.values.toList(),
    sessions: sessions.values.toList(),
    records: records.values.toList(),
    settings: {...settings},
  );

  @override
  Future<void> saveSquad(Squad squad) async {
    writes++;
    squads[squad.id] = squad;
  }

  @override
  Future<void> deleteSquad(String id) async {
    writes++;
    squads.remove(id);
    // Mirror SQLite's ON DELETE CASCADE on squad_members.
    for (final p in players.values.toList()) {
      if (p.squadIds.contains(id)) {
        players[p.id] = p.copyWith(squadIds: {...p.squadIds}..remove(id));
      }
    }
    final doomed = sessions.values.where((s) => s.squadId == id).toList();
    for (final s in doomed) {
      await deleteSession(s.id);
    }
  }

  @override
  Future<void> savePlayer(Player player) async {
    writes++;
    players[player.id] = player;
  }

  @override
  Future<void> deletePlayer(String id) async {
    writes++;
    players.remove(id);
    records.removeWhere((k, _) => k.$2 == id);
  }

  @override
  Future<void> saveSession(
    Session session, {
    List<AttendanceRecord> records = const [],
  }) async {
    writes++;
    sessions[session.id] = session;
    for (final r in records) {
      this.records[(r.sessionId, r.playerId)] = r;
    }
  }

  @override
  Future<void> deleteSession(String id) async {
    writes++;
    sessions.remove(id);
    records.removeWhere((k, _) => k.$1 == id);
  }

  @override
  Future<void> saveRecords(List<AttendanceRecord> list) async {
    writes++;
    for (final r in list) {
      records[(r.sessionId, r.playerId)] = r;
    }
  }

  @override
  Future<void> deleteRecords(List<(String, String)> keys) async {
    writes++;
    keys.forEach(records.remove);
  }

  @override
  Future<void> saveSetting(String key, String value) async {
    writes++;
    settings[key] = value;
  }

  @override
  Future<void> replaceAll(Snapshot snapshot) async {
    writes++;
    _apply(snapshot);
  }

  @override
  Future<void> close() async {}
}
