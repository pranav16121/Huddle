import 'models.dart';

/// Counts of each status. The attendance rate ignores excused absences:
///
///   rate = (present + late) / (present + late + absent)
class Tally {
  int present = 0;
  int late = 0;
  int excused = 0;
  int absent = 0;

  void add(AttendanceStatus s) {
    switch (s) {
      case AttendanceStatus.present:
        present++;
      case AttendanceStatus.late:
        late++;
      case AttendanceStatus.excused:
        excused++;
      case AttendanceStatus.absent:
        absent++;
    }
  }

  void addAll(Tally other) {
    present += other.present;
    late += other.late;
    excused += other.excused;
    absent += other.absent;
  }

  int get attended => present + late;
  int get counted => attended + absent;
  int get total => counted + excused;

  double? get rate => counted == 0 ? null : attended / counted;

  int count(AttendanceStatus s) => switch (s) {
    AttendanceStatus.present => present,
    AttendanceStatus.late => late,
    AttendanceStatus.excused => excused,
    AttendanceStatus.absent => absent,
  };

  static Tally of(Iterable<AttendanceStatus> statuses) {
    final t = Tally();
    statuses.forEach(t.add);
    return t;
  }
}

/// One line of a player's history.
typedef HistoryEntry = ({Session session, AttendanceRecord record});

class PlayerStats {
  PlayerStats({
    required this.tally,
    required this.currentStreak,
    required this.bestStreak,
    required this.missedInARow,
    required this.lastAttended,
    required this.recent,
  });

  final Tally tally;

  /// Sessions attended in a row, up to the most recent one.
  final int currentStreak;
  final int bestStreak;

  /// Sessions missed in a row, up to the most recent one.
  final int missedInARow;
  final DateTime? lastAttended;

  /// Most recent statuses, newest first (for the "form guide").
  final List<AttendanceStatus> recent;

  double? get rate => tally.rate;

  static final empty = PlayerStats(
    tally: Tally(),
    currentStreak: 0,
    bestStreak: 0,
    missedInARow: 0,
    lastAttended: null,
    recent: const [],
  );
}

/// Computes stats from a player's history, sorted newest first.
///
/// An "away" record in a session held [today] is treated as *pending* for
/// streaks: the kid might still walk in, so the streak shouldn't break (and
/// the kid shouldn't show up as "needs a nudge") in the middle of class.
PlayerStats computePlayerStats(
  List<HistoryEntry> newestFirst, {
  required DateTime today,
  int recentCount = 10,
}) {
  if (newestFirst.isEmpty) return PlayerStats.empty;

  final tally = Tally();
  for (final e in newestFirst) {
    tally.add(e.record.status);
  }

  bool pending(HistoryEntry e) =>
      e.record.status == AttendanceStatus.absent &&
      isSameDay(e.session.date, today);

  // Current streak / missed-in-a-row, walking back from the newest session.
  var current = 0;
  var missed = 0;
  var streakOpen = true;
  var missOpen = true;
  for (final e in newestFirst) {
    final s = e.record.status;
    if (s == AttendanceStatus.excused || pending(e)) continue;
    if (s.attended) {
      missOpen = false;
      if (streakOpen) current++;
    } else {
      streakOpen = false;
      if (missOpen) missed++;
    }
    if (!streakOpen && !missOpen) break;
  }

  // Best streak, walking forward in time.
  var best = 0;
  var run = 0;
  for (final e in newestFirst.reversed) {
    final s = e.record.status;
    if (s == AttendanceStatus.excused || pending(e)) continue;
    if (s.attended) {
      run++;
      if (run > best) best = run;
    } else {
      run = 0;
    }
  }

  DateTime? lastAttended;
  for (final e in newestFirst) {
    if (e.record.status.attended) {
      lastAttended = e.session.date;
      break;
    }
  }

  return PlayerStats(
    tally: tally,
    currentStreak: current,
    bestStreak: best,
    missedInARow: missed,
    lastAttended: lastAttended,
    recent: [
      for (final e in newestFirst.take(recentCount)) e.record.status,
    ],
  );
}

/// Aggregate figures across a set of sessions.
class OverviewStats {
  OverviewStats(this.sessions, this.tallies);

  /// Sessions in chronological order.
  final List<Session> sessions;
  final Map<String, Tally> tallies;

  late final Tally total = () {
    final t = Tally();
    for (final s in sessions) {
      final tally = tallies[s.id];
      if (tally != null) t.addAll(tally);
    }
    return t;
  }();

  double? get rate => total.rate;

  double? get averageTurnout =>
      sessions.isEmpty ? null : total.attended / sessions.length;

  /// Sessions where nobody was away (excused kids don't spoil a full house).
  int get fullHouses => sessions.where((s) {
    final t = tallies[s.id];
    return t != null && t.counted > 0 && t.absent == 0;
  }).length;
}

/// Monthly rates for a player's history, oldest first, for the last [months]
/// months up to and including [now]'s month.
List<({DateTime month, Tally tally})> monthlyTallies(
  List<HistoryEntry> history, {
  required DateTime now,
  int months = 6,
}) {
  final result = <({DateTime month, Tally tally})>[];
  for (var i = months - 1; i >= 0; i--) {
    final month = DateTime(now.year, now.month - i);
    result.add((month: month, tally: Tally()));
  }
  for (final e in history) {
    final d = e.session.date;
    for (final m in result) {
      if (m.month.year == d.year && m.month.month == d.month) {
        m.tally.add(e.record.status);
        break;
      }
    }
  }
  return result;
}
