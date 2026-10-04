import 'dart:io';

import 'package:attendance/data/auto_backup.dart';
import 'package:attendance/data/backup.dart';
import 'package:attendance/data/models.dart';
import 'package:attendance/data/store.dart';
import 'package:excel/excel.dart' show Excel, IntCellValue;
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';
import 'helpers.dart';

void main() {
  // Friday 2 Oct 2026, 4:30pm.
  var clock = DateTime(2026, 10, 2, 16, 30);
  late MemoryRepository repo;
  late HuddleStore store;

  setUp(() {
    clock = DateTime(2026, 10, 2, 16, 30);
    repo = MemoryRepository();
    store = HuddleStore(repo, Snapshot.empty(), clock: () => clock);
  });

  Future<HuddleStore> reload() async {
    await store.flush();
    return HuddleStore(repo, await repo.load(), clock: () => clock);
  }

  test('squads, players and memberships persist', () async {
    final squad = store.addSquad(name: ' U10 ', colorIndex: 2, weekdays: {5});
    store.addPlayers(['Maya Rodriguez', ' ', 'Leo Kim'], {squad.id});
    final again = await reload();
    expect(again.squads.single.name, 'U10');
    expect(again.membersOf(squad.id).map((p) => p.name), [
      'Leo Kim',
      'Maya Rodriguez',
    ]);
  });

  test('a session snapshots the roster and every mark is saved', () async {
    final squad = store.addSquad(name: 'U10', colorIndex: 0);
    final players = store.addPlayers(['A', 'B', 'C'], {squad.id});
    final session = store.createSession(
      squadId: squad.id,
      date: clock,
      statuses: {for (final p in players) p.id: AttendanceStatus.absent},
    );
    store.setStatus(session.id, players[0].id, AttendanceStatus.present);
    store.setStatus(session.id, players[1].id, AttendanceStatus.late);

    final again = await reload();
    final t = again.tallyOf(session.id);
    expect(t.present, 1);
    expect(t.late, 1);
    expect(t.absent, 1);
    expect(again.sessionsOn(clock, squadId: squad.id), hasLength(1));
  });

  test('rapid toggling lands in order', () async {
    final squad = store.addSquad(name: 'U10', colorIndex: 0);
    final p = store.addPlayer(name: 'Maya', squadIds: {squad.id});
    final s = store.createSession(
      squadId: squad.id,
      date: clock,
      statuses: {p.id: AttendanceStatus.absent},
    );
    for (var i = 0; i < 25; i++) {
      store.setStatus(
        s.id,
        p.id,
        i.isEven ? AttendanceStatus.present : AttendanceStatus.absent,
      );
    }
    final again = await reload();
    expect(again.statusOf(s.id, p.id), AttendanceStatus.present);
  });

  test('a player who joins mid-class appears in today\'s roll call only', () {
    final squad = store.addSquad(name: 'U10', colorIndex: 0);
    final a = store.addPlayer(name: 'A', squadIds: {squad.id});
    final past = store.createSession(
      squadId: squad.id,
      date: clock.subtract(const Duration(days: 7)),
      statuses: {a.id: AttendanceStatus.present},
    );
    final live = store.createSession(
      squadId: squad.id,
      date: clock,
      statuses: {a.id: AttendanceStatus.present},
    );
    final b = store.addPlayer(name: 'B', squadIds: {squad.id});
    expect(store.statusOf(live.id, b.id), AttendanceStatus.absent);
    expect(store.statusOf(past.id, b.id), isNull);
  });

  test('archiving drops unmarked live records but keeps real attendance', () {
    final squad = store.addSquad(name: 'U10', colorIndex: 0);
    final a = store.addPlayer(name: 'A', squadIds: {squad.id});
    final b = store.addPlayer(name: 'B', squadIds: {squad.id});
    final live = store.createSession(
      squadId: squad.id,
      date: clock,
      statuses: {a.id: AttendanceStatus.present, b.id: AttendanceStatus.absent},
    );
    store.setPlayerArchived(a.id, true);
    store.setPlayerArchived(b.id, true);
    expect(store.statusOf(live.id, a.id), AttendanceStatus.present);
    expect(store.statusOf(live.id, b.id), isNull);
    expect(store.players, isEmpty);
    expect(store.archivedPlayers, hasLength(2));
  });

  test('delete and undo a session', () async {
    final squad = store.addSquad(name: 'U10', colorIndex: 0);
    final a = store.addPlayer(name: 'A', squadIds: {squad.id});
    final s = store.createSession(
      squadId: squad.id,
      date: clock,
      statuses: {a.id: AttendanceStatus.late},
    );
    final deleted = store.deleteSession(s.id)!;
    expect(store.sessions, isEmpty);
    store.restoreSession(deleted);
    final again = await reload();
    expect(again.statusOf(s.id, a.id), AttendanceStatus.late);
  });

  test('deleting a squad removes its sessions but keeps players', () async {
    final squad = store.addSquad(name: 'U10', colorIndex: 0);
    final a = store.addPlayer(name: 'A', squadIds: {squad.id});
    store.createSession(
      squadId: squad.id,
      date: clock,
      statuses: {a.id: AttendanceStatus.present},
    );
    store.deleteSquad(squad.id);
    final again = await reload();
    expect(again.sessions, isEmpty);
    expect(again.players.single.squadIds, isEmpty);
    expect(again.historyOf(a.id), isEmpty);
  });

  test('suggested squad prefers today\'s squad closest to now, not done', () {
    final morning = store.addSquad(
      name: 'Morning',
      colorIndex: 0,
      weekdays: {DateTime.friday},
      startMinutes: 9 * 60,
    );
    final evening = store.addSquad(
      name: 'Evening',
      colorIndex: 1,
      weekdays: {DateTime.friday},
      startMinutes: 17 * 60,
    );
    store.addSquad(name: 'Monday', colorIndex: 2, weekdays: {DateTime.monday});
    expect(store.suggestedSquad()?.id, evening.id);

    clock = DateTime(2026, 10, 2, 8, 45);
    expect(store.suggestedSquad()?.id, morning.id);

    // Once the morning roll call is done, evening comes next.
    final p = store.addPlayer(name: 'A', squadIds: {morning.id});
    store.createSession(
      squadId: morning.id,
      date: clock,
      statuses: {p.id: AttendanceStatus.present},
    );
    expect(store.suggestedSquad()?.id, evening.id);
  });

  test('backup round-trips through JSON and restores', () async {
    await store.replaceAll(buildDemoSnapshot(clock));
    final before = store.snapshot();
    final text = encodeBackup(before);

    final other = HuddleStore(MemoryRepository(), Snapshot.empty());
    await other.replaceAll(decodeBackup(text));
    expect(other.squads.length, before.squads.length);
    expect(other.allPlayers.length, before.players.length);
    expect(other.sessions.length, before.sessions.length);
    for (final p in other.allPlayers) {
      expect(other.statsOf(p.id).tally.total, store.statsOf(p.id).tally.total);
    }
    expect(other.onboarded, isTrue);
  });

  test('rejects files that are not backups', () {
    expect(() => decodeBackup('hello'), throwsFormatException);
    expect(() => decodeBackup('{"format":"other"}'), throwsFormatException);
    expect(
      () => decodeBackup('{"format":"huddle-backup","version":99}'),
      throwsFormatException,
    );
  });

  group('attendance workbook', () {
    // Sheet name -> rows of cell values, with trailing empty cells dropped.
    Map<String, List<List<Object?>>> read(List<int>? bytes) => {
      for (final MapEntry(key: name, value: sheet) in Excel.decodeBytes(
        bytes!,
      ).tables.entries)
        name: [
          for (final row in sheet.rows)
            [
              for (final c in row)
                switch (c?.value) {
                  IntCellValue(:final value) => value,
                  final v => v?.toString(),
                },
            ]..length = row.lastIndexWhere((c) => c?.value != null) + 1,
        ],
    };

    test('has a sheet per month with only P or A per player per day', () {
      final squad = store.addSquad(name: 'U10', colorIndex: 0);
      final jo = store.addPlayer(name: 'Smith, Jo', squadIds: {squad.id});
      final ava = store.addPlayer(
        name: 'Ava',
        squadIds: {squad.id},
        jersey: '7',
      );
      final ben = store.addPlayer(name: 'Ben', squadIds: {squad.id});
      final cara = store.addPlayer(name: 'Cara', squadIds: {squad.id});
      // The only September session still gets its own sheet. Late and
      // excused are exported as A.
      store.createSession(
        squadId: squad.id,
        date: clock.subtract(const Duration(days: 3)),
        statuses: {
          jo.id: AttendanceStatus.present,
          ava.id: AttendanceStatus.absent,
          ben.id: AttendanceStatus.late,
          cara.id: AttendanceStatus.excused,
        },
      );
      // Two sessions on the same day make one column: present at either
      // counts as present that day.
      store.createSession(
        squadId: squad.id,
        date: clock,
        statuses: {
          jo.id: AttendanceStatus.absent,
          ava.id: AttendanceStatus.absent,
        },
      );
      store.createSession(
        squadId: squad.id,
        date: clock,
        statuses: {
          jo.id: AttendanceStatus.absent,
          ava.id: AttendanceStatus.present,
        },
      );
      // Recorded later for an earlier day: columns are still oldest first.
      store.createSession(
        squadId: squad.id,
        date: clock.subtract(const Duration(days: 1)),
        statuses: {
          jo.id: AttendanceStatus.present,
          ava.id: AttendanceStatus.late,
          ben.id: AttendanceStatus.present,
          cara.id: AttendanceStatus.excused,
        },
      );
      // Joined today: added to today's register only.
      store.addPlayer(name: 'Dev', squadIds: {squad.id});

      expect(read(buildAttendanceWorkbook(store)), {
        'September 2026': [
          ['ATTENDANCE REPORT'],
          ['September 2026'],
          [],
          ['Player', '29/09/2026', 'TOTAL ATTENDED'],
          ['Ava', 'A', 0],
          ['Ben', 'A', 0],
          ['Cara', 'A', 0],
          ['Dev', null, 0],
          ['Smith, Jo', 'P', 1],
        ],
        'October 2026': [
          ['ATTENDANCE REPORT'],
          ['October 2026'],
          [],
          ['Player', '01/10/2026', '02/10/2026', 'TOTAL ATTENDED'],
          ['Ava', 'A', 'P', 1],
          ['Ben', 'P', null, 1],
          ['Cara', 'A', null, 0],
          ['Dev', null, 'A', 0],
          ['Smith, Jo', 'P', 'A', 1],
        ],
      });
    });

    test('exporting again picks up new sessions without repeating days', () {
      final squad = store.addSquad(name: 'U10', colorIndex: 0);
      final a = store.addPlayer(name: 'Aarav', squadIds: {squad.id});
      final b = store.addPlayer(name: 'Aashi', squadIds: {squad.id});
      store.createSession(
        squadId: squad.id,
        date: clock,
        statuses: {a.id: AttendanceStatus.present, b.id: AttendanceStatus.late},
      );
      expect(read(buildAttendanceWorkbook(store)), {
        'October 2026': [
          ['ATTENDANCE REPORT'],
          ['October 2026'],
          [],
          ['Player', '02/10/2026', 'TOTAL ATTENDED'],
          ['Aarav', 'P', 1],
          ['Aashi', 'A', 0],
        ],
      });

      clock = DateTime(2026, 10, 10, 16, 30);
      store.createSession(
        squadId: squad.id,
        date: clock,
        statuses: {
          a.id: AttendanceStatus.absent,
          b.id: AttendanceStatus.present,
        },
      );
      clock = DateTime(2026, 11, 3, 16, 30);
      store.createSession(
        squadId: squad.id,
        date: clock,
        statuses: {
          a.id: AttendanceStatus.present,
          b.id: AttendanceStatus.excused,
        },
      );
      expect(read(buildAttendanceWorkbook(store)), {
        'October 2026': [
          ['ATTENDANCE REPORT'],
          ['October 2026'],
          [],
          ['Player', '02/10/2026', '10/10/2026', 'TOTAL ATTENDED'],
          ['Aarav', 'P', 'A', 1],
          ['Aashi', 'A', 'P', 1],
        ],
        'November 2026': [
          ['ATTENDANCE REPORT'],
          ['November 2026'],
          [],
          ['Player', '03/11/2026', 'TOTAL ATTENDED'],
          ['Aarav', 'P', 1],
          ['Aashi', 'A', 0],
        ],
      });
    });

    test('with several squads, each gets its own monthly sheets', () {
      Squad squad(String name) {
        clock = clock.add(const Duration(minutes: 1));
        return store.addSquad(name: name, colorIndex: 0);
      }

      final squads = [
        squad('U10'),
        squad('U12/U14'),
        squad('Under Fourteen Development'),
        squad('U10'),
      ];
      squad('No sessions yet');
      for (final s in squads) {
        final p = store.addPlayer(name: 'Aarav', squadIds: {s.id});
        store.createSession(
          squadId: s.id,
          date: clock,
          statuses: {p.id: AttendanceStatus.present},
        );
      }
      store.createSession(
        squadId: squads.first.id,
        date: clock.subtract(const Duration(days: 3)),
        statuses: {},
      );

      final sheets = read(buildAttendanceWorkbook(store));
      expect(sheets.keys, [
        'U10 - September 2026',
        'U10 - October 2026',
        'U12 U14 - October 2026',
        'Under Fourteen D - October 2026',
        'U10 2 - October 2026',
      ]);
      expect(sheets['U12 U14 - October 2026'], [
        ['ATTENDANCE REPORT'],
        ['October 2026'],
        [],
        ['Player', '02/10/2026', 'TOTAL ATTENDED'],
        ['Aarav', 'P', 1],
      ]);
    });

    test('is not built when there are no sessions', () {
      store.addSquad(name: 'U10', colorIndex: 0);
      expect(buildAttendanceWorkbook(store), isNull);
    });
  });

  test('demo data is realistic', () {
    final demo = buildDemoSnapshot(clock);
    final s = HuddleStore(MemoryRepository(), demo, clock: () => clock);
    // One squad trains today so roll call can be tried straight away.
    expect(s.suggestedSquad(), isNotNull);
    expect(s.sessionsOn(clock), isEmpty);
    // Someone is drifting away and someone is on a streak.
    expect(s.players.any((p) => s.statsOf(p.id).missedInARow >= 2), isTrue);
    expect(s.players.any((p) => s.statsOf(p.id).currentStreak >= 5), isTrue);
  });

  group('demo cleanup', () {
    test(
      'removes the sample season but keeps everything the coach added',
      () async {
        final demo = buildDemoSnapshot(clock)..settings['onboarded'] = 'true';
        await repo.replaceAll(demo);
        store = HuddleStore(repo, await repo.load(), clock: () => clock);
        expect(store.hasDemoData, isTrue);

        // The coach used a demo squad for real: added a kid, took a roll call.
        final juniors = store.squad('demo-juniors')!;
        final real = store.addPlayer(name: 'Real Kid', squadIds: {juniors.id});
        final session = store.createSession(
          squadId: juniors.id,
          date: clock,
          statuses: {
            real.id: AttendanceStatus.present,
            'demo-juniors-1': AttendanceStatus.present,
          },
        );
        final ownSquad = store.addSquad(name: 'My U12', colorIndex: 3);

        final copies = <String>[];
        store.beforeDestructive = (before, reason) async => copies.add(reason);
        final removed = await store.removeDemoData();
        expect(removed, greaterThan(20));
        expect(copies, ['remove-demo']);

        final again = await reload();
        expect(again.hasDemoData, isFalse);
        expect(again.allPlayers.map((p) => p.name), ['Real Kid']);
        // The demo squad they actually used stays; the unused one is gone.
        expect(again.allSquads.map((s) => s.id), {juniors.id, ownSquad.id});
        expect(again.sessions.single.id, session.id);
        expect(again.statusOf(session.id, real.id), AttendanceStatus.present);
        expect(again.recordsOf(session.id).keys, [real.id]);
        expect(again.onboarded, isTrue);
      },
    );

    test(
      'with nothing of their own, the coach gets the setup screen',
      () async {
        final demo = buildDemoSnapshot(clock)..settings['onboarded'] = 'true';
        await repo.replaceAll(demo);
        store = HuddleStore(repo, await repo.load(), clock: () => clock);
        await store.removeDemoData();
        final again = await reload();
        expect(again.allSquads, isEmpty);
        expect(again.allPlayers, isEmpty);
        expect(again.sessions, isEmpty);
        expect(again.onboarded, isFalse);
        expect(again.hasDemoData, isFalse);
      },
    );

    test('runs once: not again on the next launch, but again if an old demo '
        'backup is restored', () async {
      final demo = buildDemoSnapshot(clock)..settings['onboarded'] = 'true';
      final oldBackup = decodeBackup(encodeBackup(demo));
      await repo.replaceAll(demo);
      store = HuddleStore(repo, await repo.load(), clock: () => clock);
      store.addPlayer(name: 'Real Kid', squadIds: {'demo-juniors'});
      await store.removeDemoData();
      var again = await reload();
      expect(again.hasDemoData, isFalse);

      await again.replaceAll(oldBackup);
      expect(again.hasDemoData, isTrue);
    });

    test('does nothing for a coach who never used the demo', () async {
      store.addSquad(name: 'U10', colorIndex: 0);
      var called = false;
      store.beforeDestructive = (_, _) async => called = true;
      expect(store.hasDemoData, isFalse);
      expect(await store.removeDemoData(), 0);
      expect(called, isFalse);
      expect(store.squads, hasLength(1));
    });
  });

  group('automatic backups', () {
    late Directory dir;
    late AutoBackups backups;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('huddle_backups_');
      backups = AutoBackups(dir)..attach(store);
    });

    tearDown(() => dir.deleteSync(recursive: true));

    test('daily backup is written once per change, and never empty', () async {
      await backups.daily(store);
      expect(await backups.list(), isEmpty); // nothing to back up yet

      store.addSquad(name: 'U10', colorIndex: 0);
      await backups.daily(store);
      final first = await backups.list();
      expect(first.single.kind, AutoBackupKind.daily);
      final stamp = first.single.file.lastModifiedSync();

      await backups.daily(store); // unchanged: skipped
      expect(first.single.file.lastModifiedSync(), stamp);

      final restored = await first.single.read();
      expect(restored.squads.single.name, 'U10');
    });

    test('a safety copy is made before deleting and restoring', () async {
      final squad = store.addSquad(name: 'U10', colorIndex: 0);
      final kid = store.addPlayer(name: 'Maya', squadIds: {squad.id});
      store.createSession(
        squadId: squad.id,
        date: clock,
        statuses: {kid.id: AttendanceStatus.present},
      );

      store.deletePlayer(kid.id);
      store.deleteSquad(squad.id);
      await store.flush();

      final safety = (await backups.list())
          .where((b) => b.kind == AutoBackupKind.safety)
          .toList();
      expect(safety.map((b) => b.reason).toSet(), {
        'delete-player',
        'delete-squad',
      });
      // The copy made before deleting the player still has everything.
      final beforePlayer = safety.firstWhere(
        (b) => b.reason == 'delete-player',
      );
      final snap = await beforePlayer.read();
      expect(snap.players.single.name, 'Maya');
      expect(snap.sessions, hasLength(1));
      expect(snap.records.single.status, AttendanceStatus.present);

      // Restoring it brings Maya and her attendance back...
      store.addSquad(name: 'Made since', colorIndex: 1);
      await store.replaceAll(snap);
      expect(store.players.single.name, 'Maya');
      expect(store.historyOf(kid.id), hasLength(1));
      // ...and what was there just before is itself kept.
      await store.flush();
      final beforeRestore = (await backups.list()).firstWhere(
        (b) => b.reason == 'restore',
      );
      expect((await beforeRestore.read()).squads.single.name, 'Made since');
    });

    test('old copies are pruned', () async {
      store.addSquad(name: 'U10', colorIndex: 0);
      for (var i = 0; i < AutoBackups.keepSafety + 5; i++) {
        await backups.safety(store.snapshot(), 'delete-session');
      }
      final safety = (await backups.list()).where(
        (b) => b.kind == AutoBackupKind.safety,
      );
      expect(safety, hasLength(AutoBackups.keepSafety));
    });
  });
}
