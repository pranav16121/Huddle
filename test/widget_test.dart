import 'package:attendance/app.dart';
import 'package:attendance/data/models.dart';
import 'package:attendance/data/store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';
import 'helpers.dart';

void main() {
  final now = DateTime(2026, 10, 2, 16, 30);

  /// Pumps real frames (unlike a single pump(duration)) so animations run.
  Future<void> settle(WidgetTester tester, [int ms = 600]) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(Duration(milliseconds: ms ~/ 12));
    }
  }

  Snapshot demo() {
    final s = buildDemoSnapshot(now);
    s.settings['onboarded'] = 'true';
    return s;
  }

  Future<HuddleStore> pumpApp(WidgetTester tester, Snapshot snapshot) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final store = HuddleStore(MemoryRepository(), snapshot, clock: () => now);
    await tester.pumpWidget(HuddleApp(store: store));
    await settle(tester, 600);
    return store;
  }

  testWidgets('first launch shows the welcome screen', (tester) async {
    await pumpApp(tester, Snapshot.empty());
    expect(find.text('HUDDLE'), findsOneWidget);
    expect(find.text('Set up my squad'), findsOneWidget);
    // No demo any more: the only way in is setting up your own squad.
    expect(find.textContaining('demo'), findsNothing);
  });

  testWidgets('onboarding creates a squad with pasted players', (tester) async {
    final store = await pumpApp(tester, Snapshot.empty());
    await tester.tap(find.text('Set up my squad'));
    await settle(tester, 500);

    await tester.enterText(
      find.widgetWithText(TextField, 'Squad name'),
      'U10 Saturday',
    );
    await tester.pump();
    await tester.tap(find.text('Next'));
    await settle(tester, 500);

    await tester.enterText(
      find.byType(TextField).last,
      'Maya Rodriguez\nLeo Kim\nAva Thompson',
    );
    await tester.pump();
    expect(find.text('Add 3 players'), findsOneWidget);
    await tester.tap(find.text('Add 3 players'));
    await settle(tester, 600);

    expect(store.onboarded, isTrue);
    expect(store.squads.single.name, 'U10 Saturday');
    expect(store.players, hasLength(3));
    // Only one squad, so it's the hero on Today even with no training days.
    expect(find.text('Start roll call'), findsOneWidget);
  });

  testWidgets('roll call: tap to mark, rest are here, summary', (tester) async {
    final store = await pumpApp(tester, demo());
    final squad = store.suggestedSquad()!;
    final members = store.membersOf(squad.id);

    await tester.tap(find.text('Start roll call'));
    await settle(tester, 600);
    expect(find.text('Tap a player when they arrive.\nHold for Late or Excused.'),
        findsOneWidget);

    // Nothing is saved until someone is marked.
    expect(store.sessionsOn(now, squadId: squad.id), isEmpty);

    final first = members.first;
    await tester.tap(find.text(first.firstName).first);
    await settle(tester, 400);
    final session = store.sessionsOn(now, squadId: squad.id).single;
    expect(store.statusOf(session.id, first.id), AttendanceStatus.present);
    expect(find.text('Done · 1/${members.length}'), findsOneWidget);

    // Tap again to undo.
    await tester.tap(find.text(first.firstName).first);
    await settle(tester, 400);
    expect(store.statusOf(session.id, first.id), AttendanceStatus.absent);

    await tester.tap(find.text('Rest are here'));
    await settle(tester, 1000);
    expect(store.tallyOf(session.id).absent, 0);
    expect(find.text('Done · ${members.length}/${members.length}'),
        findsOneWidget);

    await tester.tap(find.text('Done · ${members.length}/${members.length}'));
    await settle(tester, 600);
    expect(find.text('Full house!'), findsOneWidget);
    await settle(tester, 3000);
  });

  testWidgets('leaving an empty roll call saves nothing', (tester) async {
    final store = await pumpApp(tester, demo());
    final before = store.sessions.length;
    await tester.tap(find.text('Start roll call'));
    await settle(tester, 600);
    await tester.pageBack();
    await settle(tester, 600);
    expect(store.sessions.length, before);
    expect(find.text('Start roll call'), findsOneWidget);
  });

  testWidgets('every tab renders with demo data', (tester) async {
    await pumpApp(tester, demo());
    for (final tab in ['Roster', 'History', 'Stats', 'Today']) {
      await tester.tap(find.text(tab).last);
      await settle(tester, 1200);
      expect(tester.takeException(), isNull);
    }
    await tester.tap(find.text('Stats').last);
    await settle(tester, 600);
    expect(find.text('MOST RELIABLE'), findsOneWidget);
  });
}
