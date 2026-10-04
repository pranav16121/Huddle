import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'models.dart';

/// Persistence boundary. The app keeps everything in memory for instant UI
/// and writes through to a [Repository] on every change.
abstract class Repository {
  Future<Snapshot> load();

  Future<void> saveSquad(Squad squad);
  Future<void> deleteSquad(String id);

  Future<void> savePlayer(Player player);
  Future<void> deletePlayer(String id);

  /// Inserts or updates [session] and, optionally, a batch of its records in
  /// a single transaction.
  Future<void> saveSession(
    Session session, {
    List<AttendanceRecord> records = const [],
  });
  Future<void> deleteSession(String id);

  Future<void> saveRecords(List<AttendanceRecord> records);
  Future<void> deleteRecords(List<(String sessionId, String playerId)> keys);

  Future<void> saveSetting(String key, String value);

  /// Atomically wipes all data and replaces it with [snapshot].
  Future<void> replaceAll(Snapshot snapshot);

  Future<void> close();
}

class SqliteRepository implements Repository {
  SqliteRepository._(this._db);

  final Database _db;

  static const fileName = 'huddle.db';
  static const _version = 1;

  /// Opens (and creates or migrates) the on-device database.
  static Future<SqliteRepository> open({
    DatabaseFactory? factory,
    String? path,
  }) async {
    final f = factory ?? databaseFactory;
    final dbPath = path ?? p.join(await f.getDatabasesPath(), fileName);
    final db = await f.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: _version,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (db, version) async {
          final batch = db.batch();
          _createSchema(batch);
          await batch.commit(noResult: true);
        },
        // Future schema changes go here, keyed on oldVersion.
        onUpgrade: (db, oldVersion, newVersion) async {},
      ),
    );
    return SqliteRepository._(db);
  }

  static void _createSchema(Batch b) {
    b.execute('''
      CREATE TABLE squads (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        color INTEGER NOT NULL,
        weekdays TEXT NOT NULL,
        start_minutes INTEGER,
        archived INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL
      )''');
    b.execute('''
      CREATE TABLE players (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        jersey TEXT,
        notes TEXT NOT NULL DEFAULT '',
        archived INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL
      )''');
    b.execute('''
      CREATE TABLE squad_members (
        squad_id TEXT NOT NULL REFERENCES squads(id) ON DELETE CASCADE,
        player_id TEXT NOT NULL REFERENCES players(id) ON DELETE CASCADE,
        PRIMARY KEY (squad_id, player_id)
      )''');
    b.execute('''
      CREATE TABLE sessions (
        id TEXT PRIMARY KEY,
        squad_id TEXT NOT NULL REFERENCES squads(id) ON DELETE CASCADE,
        date TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        note TEXT NOT NULL DEFAULT ''
      )''');
    b.execute('CREATE INDEX sessions_by_squad ON sessions(squad_id, date)');
    b.execute('''
      CREATE TABLE records (
        session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
        player_id TEXT NOT NULL REFERENCES players(id) ON DELETE CASCADE,
        status TEXT NOT NULL,
        updated_at INTEGER NOT NULL,
        PRIMARY KEY (session_id, player_id)
      )''');
    b.execute('CREATE INDEX records_by_player ON records(player_id)');
    b.execute('''
      CREATE TABLE settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )''');
  }

  @override
  Future<Snapshot> load() async {
    final squadRows = await _db.query('squads', orderBy: 'created_at');
    final playerRows = await _db.query('players', orderBy: 'created_at');
    final memberRows = await _db.query('squad_members');
    final sessionRows = await _db.query('sessions');
    final recordRows = await _db.query('records');
    final settingRows = await _db.query('settings');

    final memberships = <String, Set<String>>{};
    for (final row in memberRows) {
      memberships
          .putIfAbsent(row['player_id'] as String, () => {})
          .add(row['squad_id'] as String);
    }

    return Snapshot(
      squads: [
        for (final r in squadRows)
          Squad(
            id: r['id'] as String,
            name: r['name'] as String,
            colorIndex: r['color'] as int,
            weekdays: {
              for (final d in (r['weekdays'] as String).split(','))
                if (d.isNotEmpty) int.parse(d),
            },
            startMinutes: r['start_minutes'] as int?,
            archived: (r['archived'] as int) == 1,
            createdAt: DateTime.fromMillisecondsSinceEpoch(
              r['created_at'] as int,
            ),
          ),
      ],
      players: [
        for (final r in playerRows)
          Player(
            id: r['id'] as String,
            name: r['name'] as String,
            jersey: r['jersey'] as String?,
            notes: r['notes'] as String,
            archived: (r['archived'] as int) == 1,
            squadIds: memberships[r['id']] ?? {},
            createdAt: DateTime.fromMillisecondsSinceEpoch(
              r['created_at'] as int,
            ),
          ),
      ],
      sessions: [
        for (final r in sessionRows)
          Session(
            id: r['id'] as String,
            squadId: r['squad_id'] as String,
            date: parseDateKey(r['date'] as String),
            createdAt: DateTime.fromMillisecondsSinceEpoch(
              r['created_at'] as int,
            ),
            note: r['note'] as String,
          ),
      ],
      records: [
        for (final r in recordRows)
          AttendanceRecord(
            sessionId: r['session_id'] as String,
            playerId: r['player_id'] as String,
            status: AttendanceStatus.fromCode(r['status'] as String),
            updatedAt: DateTime.fromMillisecondsSinceEpoch(
              r['updated_at'] as int,
            ),
          ),
      ],
      settings: {
        for (final r in settingRows) r['key'] as String: r['value'] as String,
      },
    );
  }

  // -- Row mapping ----------------------------------------------------------

  static Map<String, Object?> _squadRow(Squad s) => {
    'id': s.id,
    'name': s.name,
    'color': s.colorIndex,
    'weekdays': (s.weekdays.toList()..sort()).join(','),
    'start_minutes': s.startMinutes,
    'archived': s.archived ? 1 : 0,
    'created_at': s.createdAt.millisecondsSinceEpoch,
  };

  static Map<String, Object?> _playerRow(Player pl) => {
    'id': pl.id,
    'name': pl.name,
    'jersey': pl.jersey,
    'notes': pl.notes,
    'archived': pl.archived ? 1 : 0,
    'created_at': pl.createdAt.millisecondsSinceEpoch,
  };

  static Map<String, Object?> _sessionRow(Session s) => {
    'id': s.id,
    'squad_id': s.squadId,
    'date': dateKey(s.date),
    'created_at': s.createdAt.millisecondsSinceEpoch,
    'note': s.note,
  };

  static Map<String, Object?> _recordRow(AttendanceRecord r) => {
    'session_id': r.sessionId,
    'player_id': r.playerId,
    'status': r.status.code,
    'updated_at': r.updatedAt.millisecondsSinceEpoch,
  };

  // Upserts use ON CONFLICT DO UPDATE rather than INSERT OR REPLACE, because
  // REPLACE deletes the old row first, which would cascade-delete children.
  static Future<void> _upsert(
    DatabaseExecutor db,
    String table,
    Map<String, Object?> row,
    List<String> keys,
  ) {
    final cols = row.keys.toList();
    final updates = cols
        .where((c) => !keys.contains(c))
        .map((c) => '$c = excluded.$c')
        .join(', ');
    final sql =
        'INSERT INTO $table (${cols.join(', ')}) '
        'VALUES (${List.filled(cols.length, '?').join(', ')}) '
        'ON CONFLICT(${keys.join(', ')}) DO '
        '${updates.isEmpty ? 'NOTHING' : 'UPDATE SET $updates'}';
    return db.execute(sql, row.values.toList());
  }

  static Future<void> _writePlayer(DatabaseExecutor db, Player pl) async {
    await _upsert(db, 'players', _playerRow(pl), ['id']);
    await db.delete('squad_members', where: 'player_id = ?', whereArgs: [pl.id]);
    for (final squadId in pl.squadIds) {
      await db.insert('squad_members', {
        'squad_id': squadId,
        'player_id': pl.id,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  // -- Writes ---------------------------------------------------------------

  @override
  Future<void> saveSquad(Squad squad) =>
      _upsert(_db, 'squads', _squadRow(squad), ['id']);

  @override
  Future<void> deleteSquad(String id) =>
      _db.delete('squads', where: 'id = ?', whereArgs: [id]);

  @override
  Future<void> savePlayer(Player player) =>
      _db.transaction((txn) => _writePlayer(txn, player));

  @override
  Future<void> deletePlayer(String id) =>
      _db.delete('players', where: 'id = ?', whereArgs: [id]);

  @override
  Future<void> saveSession(
    Session session, {
    List<AttendanceRecord> records = const [],
  }) {
    return _db.transaction((txn) async {
      await _upsert(txn, 'sessions', _sessionRow(session), ['id']);
      for (final r in records) {
        await _upsert(txn, 'records', _recordRow(r), [
          'session_id',
          'player_id',
        ]);
      }
    });
  }

  @override
  Future<void> deleteSession(String id) =>
      _db.delete('sessions', where: 'id = ?', whereArgs: [id]);

  @override
  Future<void> saveRecords(List<AttendanceRecord> records) {
    if (records.isEmpty) return Future.value();
    return _db.transaction((txn) async {
      for (final r in records) {
        await _upsert(txn, 'records', _recordRow(r), [
          'session_id',
          'player_id',
        ]);
      }
    });
  }

  @override
  Future<void> deleteRecords(List<(String, String)> keys) {
    if (keys.isEmpty) return Future.value();
    return _db.transaction((txn) async {
      for (final (sessionId, playerId) in keys) {
        await txn.delete(
          'records',
          where: 'session_id = ? AND player_id = ?',
          whereArgs: [sessionId, playerId],
        );
      }
    });
  }

  @override
  Future<void> saveSetting(String key, String value) =>
      _upsert(_db, 'settings', {'key': key, 'value': value}, ['key']);

  @override
  Future<void> replaceAll(Snapshot s) {
    return _db.transaction((txn) async {
      // Children first, so foreign keys never complain.
      for (final table in [
        'records',
        'sessions',
        'squad_members',
        'players',
        'squads',
        'settings',
      ]) {
        await txn.delete(table);
      }
      for (final squad in s.squads) {
        await txn.insert('squads', _squadRow(squad));
      }
      for (final player in s.players) {
        await _writePlayer(txn, player);
      }
      for (final session in s.sessions) {
        await txn.insert('sessions', _sessionRow(session));
      }
      for (final record in s.records) {
        await txn.insert('records', _recordRow(record));
      }
      for (final e in s.settings.entries) {
        await txn.insert('settings', {'key': e.key, 'value': e.value});
      }
    });
  }

  @override
  Future<void> close() => _db.close();
}
