import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show StringCharacters;

/// How a player was recorded for a single session.
///
/// Every player in a session has exactly one status. Players that the coach
/// has not tapped stay [absent], so a roll call is always complete and can be
/// abandoned at any moment without leaving half-recorded data behind.
enum AttendanceStatus {
  present('P', 'Here'),
  late('L', 'Late'),
  excused('E', 'Excused'),
  absent('A', 'Away');

  const AttendanceStatus(this.code, this.label);

  /// Compact, stable code used in storage and backups.
  final String code;

  /// Human label shown in the UI.
  final String label;

  /// Showed up for the session (on time or not).
  bool get attended => this == present || this == late;

  /// Whether this status counts toward the attendance rate. Excused absences
  /// (sick, family trip, told the coach in advance) never count against a kid.
  bool get counts => this != excused;

  static AttendanceStatus fromCode(String code) => values.firstWhere(
    (s) => s.code == code,
    orElse: () => AttendanceStatus.absent,
  );
}

@immutable
class Squad {
  const Squad({
    required this.id,
    required this.name,
    required this.colorIndex,
    required this.weekdays,
    required this.createdAt,
    this.startMinutes,
    this.archived = false,
  });

  final String id;
  final String name;
  final int colorIndex;

  /// Training days using [DateTime.monday]..[DateTime.sunday].
  final Set<int> weekdays;

  /// Usual start time in minutes after midnight, if the coach set one.
  final int? startMinutes;
  final bool archived;
  final DateTime createdAt;

  bool trainsOn(DateTime day) => weekdays.contains(day.weekday);

  Squad copyWith({
    String? name,
    int? colorIndex,
    Set<int>? weekdays,
    int? Function()? startMinutes,
    bool? archived,
  }) {
    return Squad(
      id: id,
      name: name ?? this.name,
      colorIndex: colorIndex ?? this.colorIndex,
      weekdays: weekdays ?? this.weekdays,
      startMinutes: startMinutes != null ? startMinutes() : this.startMinutes,
      archived: archived ?? this.archived,
      createdAt: createdAt,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'color': colorIndex,
    'weekdays': weekdays.toList()..sort(),
    'startMinutes': startMinutes,
    'archived': archived,
    'createdAt': createdAt.millisecondsSinceEpoch,
  };

  factory Squad.fromJson(Map<String, Object?> json) => Squad(
    id: json['id'] as String,
    name: json['name'] as String,
    colorIndex: (json['color'] as num?)?.toInt() ?? 0,
    weekdays: {
      for (final d in (json['weekdays'] as List? ?? const [])) (d as num).toInt(),
    },
    startMinutes: (json['startMinutes'] as num?)?.toInt(),
    archived: json['archived'] == true,
    createdAt: DateTime.fromMillisecondsSinceEpoch(
      (json['createdAt'] as num?)?.toInt() ?? 0,
    ),
  );
}

@immutable
class Player {
  const Player({
    required this.id,
    required this.name,
    required this.squadIds,
    required this.createdAt,
    this.jersey,
    this.notes = '',
    this.archived = false,
  });

  final String id;
  final String name;

  /// Optional jersey / bib number, shown on the player's avatar.
  final String? jersey;
  final Set<String> squadIds;
  final String notes;
  final bool archived;
  final DateTime createdAt;

  String get firstName => name.trim().split(RegExp(r'\s+')).first;

  /// "Maya Rodriguez" -> "Maya R."
  String get shortName {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length < 2) return parts.first;
    return '${parts.first} ${parts.last.characters.first.toUpperCase()}.';
  }

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      return parts.first.characters.take(2).toString().toUpperCase();
    }
    return (parts.first.characters.first + parts.last.characters.first)
        .toUpperCase();
  }

  Player copyWith({
    String? name,
    String? Function()? jersey,
    Set<String>? squadIds,
    String? notes,
    bool? archived,
  }) {
    return Player(
      id: id,
      name: name ?? this.name,
      jersey: jersey != null ? jersey() : this.jersey,
      squadIds: squadIds ?? this.squadIds,
      notes: notes ?? this.notes,
      archived: archived ?? this.archived,
      createdAt: createdAt,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'jersey': jersey,
    'squads': squadIds.toList(),
    'notes': notes,
    'archived': archived,
    'createdAt': createdAt.millisecondsSinceEpoch,
  };

  factory Player.fromJson(Map<String, Object?> json) => Player(
    id: json['id'] as String,
    name: json['name'] as String,
    jersey: json['jersey'] as String?,
    squadIds: {for (final s in (json['squads'] as List? ?? const [])) s as String},
    notes: json['notes'] as String? ?? '',
    archived: json['archived'] == true,
    createdAt: DateTime.fromMillisecondsSinceEpoch(
      (json['createdAt'] as num?)?.toInt() ?? 0,
    ),
  );
}

@immutable
class Session {
  const Session({
    required this.id,
    required this.squadId,
    required this.date,
    required this.createdAt,
    this.note = '',
  });

  final String id;
  final String squadId;

  /// Local calendar day of the session (time component is always midnight).
  final DateTime date;
  final DateTime createdAt;
  final String note;

  Session copyWith({DateTime? date, String? note}) => Session(
    id: id,
    squadId: squadId,
    date: date ?? this.date,
    createdAt: createdAt,
    note: note ?? this.note,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'squad': squadId,
    'date': dateKey(date),
    'createdAt': createdAt.millisecondsSinceEpoch,
    'note': note,
  };

  factory Session.fromJson(Map<String, Object?> json) => Session(
    id: json['id'] as String,
    squadId: json['squad'] as String,
    date: parseDateKey(json['date'] as String),
    createdAt: DateTime.fromMillisecondsSinceEpoch(
      (json['createdAt'] as num?)?.toInt() ?? 0,
    ),
    note: json['note'] as String? ?? '',
  );
}

@immutable
class AttendanceRecord {
  const AttendanceRecord({
    required this.sessionId,
    required this.playerId,
    required this.status,
    required this.updatedAt,
  });

  final String sessionId;
  final String playerId;
  final AttendanceStatus status;
  final DateTime updatedAt;

  AttendanceRecord withStatus(AttendanceStatus status, DateTime at) =>
      AttendanceRecord(
        sessionId: sessionId,
        playerId: playerId,
        status: status,
        updatedAt: at,
      );

  Map<String, Object?> toJson() => {
    'session': sessionId,
    'player': playerId,
    'status': status.code,
    'updatedAt': updatedAt.millisecondsSinceEpoch,
  };

  factory AttendanceRecord.fromJson(Map<String, Object?> json) =>
      AttendanceRecord(
        sessionId: json['session'] as String,
        playerId: json['player'] as String,
        status: AttendanceStatus.fromCode(json['status'] as String),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(
          (json['updatedAt'] as num?)?.toInt() ?? 0,
        ),
      );
}

/// Everything the app knows, in one immutable bundle. Used for loading,
/// backups, restores and demo data.
class Snapshot {
  Snapshot({
    required this.squads,
    required this.players,
    required this.sessions,
    required this.records,
    Map<String, String>? settings,
  }) : settings = settings ?? {};

  Snapshot.empty()
    : squads = [],
      players = [],
      sessions = [],
      records = [],
      settings = {};

  final List<Squad> squads;
  final List<Player> players;
  final List<Session> sessions;
  final List<AttendanceRecord> records;
  final Map<String, String> settings;

  static const formatId = 'huddle-backup';
  static const formatVersion = 1;

  Map<String, Object?> toJson() => {
    'format': formatId,
    'version': formatVersion,
    'exportedAt': DateTime.now().toIso8601String(),
    'squads': [for (final s in squads) s.toJson()],
    'players': [for (final p in players) p.toJson()],
    'sessions': [for (final s in sessions) s.toJson()],
    'records': [for (final r in records) r.toJson()],
    'settings': settings,
  };

  /// Parses a backup file. Throws [FormatException] if it isn't one of ours.
  factory Snapshot.fromJson(Map<String, Object?> json) {
    if (json['format'] != formatId) {
      throw const FormatException('This file is not a Huddle backup.');
    }
    final version = (json['version'] as num?)?.toInt() ?? 0;
    if (version > formatVersion) {
      throw const FormatException(
        'This backup was made by a newer version of Huddle.',
      );
    }
    List<Map<String, Object?>> list(String key) => [
      for (final e in (json[key] as List? ?? const []))
        (e as Map).cast<String, Object?>(),
    ];
    final squads = list('squads').map(Squad.fromJson).toList();
    final squadIds = {for (final s in squads) s.id};
    final players = list('players').map(Player.fromJson).map((p) {
      // Drop memberships pointing at squads that aren't in the file.
      return p.copyWith(squadIds: p.squadIds.where(squadIds.contains).toSet());
    }).toList();
    final playerIds = {for (final p in players) p.id};
    final sessions = list(
      'sessions',
    ).map(Session.fromJson).where((s) => squadIds.contains(s.squadId)).toList();
    final sessionIds = {for (final s in sessions) s.id};
    final records = list('records')
        .map(AttendanceRecord.fromJson)
        .where(
          (r) =>
              sessionIds.contains(r.sessionId) &&
              playerIds.contains(r.playerId),
        )
        .toList();
    return Snapshot(
      squads: squads,
      players: players,
      sessions: sessions,
      records: records,
      settings: {
        for (final e
            in ((json['settings'] as Map?) ?? const {}).entries)
          e.key as String: e.value as String,
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

final _random = Random.secure();

/// Short, sortable, collision-resistant id. No package needed.
String newId() {
  final time = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  final rand = List.generate(
    6,
    (_) => _random.nextInt(36).toRadixString(36),
  ).join();
  return '$time$rand';
}

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

String dateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

DateTime parseDateKey(String key) {
  final parts = key.split('-').map(int.parse).toList();
  return DateTime(parts[0], parts[1], parts[2]);
}

bool isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
