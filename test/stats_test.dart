import 'package:attendance/data/models.dart';
import 'package:attendance/data/stats.dart';
import 'package:attendance/ui/screens/roster_screen.dart' show parseNames;
import 'package:flutter_test/flutter_test.dart';

const P = AttendanceStatus.present;
const L = AttendanceStatus.late;
const E = AttendanceStatus.excused;
const A = AttendanceStatus.absent;

final today = DateTime(2026, 10, 2);

/// Builds a history (newest first) from statuses listed oldest → newest, one
/// session per day ending yesterday (or today if [endsToday]).
List<HistoryEntry> history(List<AttendanceStatus> oldestFirst, {bool endsToday = false}) {
  final n = oldestFirst.length;
  final entries = <HistoryEntry>[];
  for (var i = 0; i < n; i++) {
    final daysAgo = (n - 1 - i) + (endsToday ? 0 : 1);
    final date = today.subtract(Duration(days: daysAgo));
    final s = Session(id: 's$i', squadId: 'q', date: date, createdAt: date);
    entries.add((
      session: s,
      record: AttendanceRecord(
        sessionId: s.id,
        playerId: 'p',
        status: oldestFirst[i],
        updatedAt: date,
      ),
    ));
  }
  return entries.reversed.toList();
}

void main() {
  group('Tally', () {
    test('rate ignores excused absences', () {
      final t = Tally.of([P, L, E, A]);
      expect(t.attended, 2);
      expect(t.counted, 3);
      expect(t.total, 4);
      expect(t.rate, closeTo(2 / 3, 1e-9));
    });

    test('rate is null when nothing counts', () {
      expect(Tally().rate, isNull);
      expect(Tally.of([E, E]).rate, isNull);
    });
  });

  group('computePlayerStats', () {
    test('empty history', () {
      final s = computePlayerStats([], today: today);
      expect(s.rate, isNull);
      expect(s.currentStreak, 0);
      expect(s.bestStreak, 0);
      expect(s.lastAttended, isNull);
    });

    test('current and best streaks; late counts as attended', () {
      final s = computePlayerStats(
        history([P, P, P, P, A, P, L, P]),
        today: today,
      );
      expect(s.currentStreak, 3);
      expect(s.bestStreak, 4);
      expect(s.missedInARow, 0);
      expect(s.tally.attended, 7);
    });

    test('excused does not break a streak', () {
      final s = computePlayerStats(history([P, E, P, E, P]), today: today);
      expect(s.currentStreak, 3);
      expect(s.bestStreak, 3);
      expect(s.rate, 1.0);
    });

    test('missed in a row counts trailing absences', () {
      final s = computePlayerStats(history([P, P, A, E, A, A]), today: today);
      expect(s.missedInARow, 3);
      expect(s.currentStreak, 0);
      expect(s.lastAttended, today.subtract(const Duration(days: 5)));
    });

    test('an unmarked kid today is pending, not a broken streak', () {
      final s = computePlayerStats(
        history([P, P, P, A], endsToday: true),
        today: today,
      );
      expect(s.currentStreak, 3);
      expect(s.missedInARow, 0);
      // ...but still counts in today's rate.
      expect(s.tally.absent, 1);
    });

    test('form guide is newest first and capped', () {
      final s = computePlayerStats(
        history([A, A, P, L, E, P, P, P, P, P, P, A]),
        today: today,
      );
      expect(s.recent.length, 10);
      expect(s.recent.first, A);
    });
  });

  test('monthlyTallies buckets by month, oldest first', () {
    final m = monthlyTallies(history([P, A, P]), now: today, months: 3);
    expect(m.map((e) => e.month.month), [8, 9, 10]);
    // Sep 29, 30 and Oct 1.
    expect(m[1].tally.total, 2);
    expect(m[2].tally.total, 1);
  });

  group('parseNames', () {
    test('one per line, trims, removes bullets & numbering & duplicates', () {
      expect(
        parseNames(' 1. Maya Rodriguez\n- Leo   Kim\n\n• Ava\n2) maya rodriguez\n'),
        ['Maya Rodriguez', 'Leo Kim', 'Ava'],
      );
    });

    test('single line falls back to commas', () {
      expect(parseNames('Maya, Leo,Ava'), ['Maya', 'Leo', 'Ava']);
    });
  });

  group('Player names', () {
    Player p(String name) =>
        Player(id: 'x', name: name, squadIds: const {}, createdAt: today);

    test('initials and short names', () {
      expect(p('Maya Rodriguez').initials, 'MR');
      expect(p('Maya Rodriguez').shortName, 'Maya R.');
      expect(p('Leo').initials, 'LE');
      expect(p('Kiara D\'Souza Lobo').initials, 'KL');
      expect(p('  Ava   Thompson ').firstName, 'Ava');
    });
  });
}
