import 'package:attendance/app.dart';
import 'package:attendance/data/models.dart';
import 'package:attendance/data/store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';
import 'helpers.dart';

/// Walks through every screen, sheet and dialog on small phones with large
/// text, and fails with a list of every layout overflow found.
void main() {
  final now = DateTime(2026, 10, 2, 16, 30);

  const devices = [
    // OnePlus 7 (1080x2340 @ 450dpi) with the largest font size: 1.35.
    (
      name: 'OnePlus 7, font 1.35',
      width: 1080.0,
      height: 2340.0,
      dpr: 2.8125,
      scale: 1.35,
    ),
    // A small, common Android phone with large text.
    (
      name: '360dp phone, font 1.5',
      width: 1080.0,
      height: 2160.0,
      dpr: 3.0,
      scale: 1.5,
    ),
  ];

  // Measure with the app's real fonts, not the test font (whose glyphs are
  // all full-width squares).
  setUpAll(() async {
    final families = {
      'Barlow': ['Regular', 'Medium', 'SemiBold', 'Bold'],
      'BarlowCondensed': ['SemiBold', 'Bold', 'ExtraBold'],
    };
    for (final MapEntry(key: family, value: weights) in families.entries) {
      final loader = FontLoader(family);
      for (final w in weights) {
        loader.addFont(rootBundle.load('assets/fonts/$family-$w.ttf'));
      }
      await loader.load();
    }
  });

  for (final (device, longNames) in [
    for (final d in devices) ...[(d, false), (d, true)],
  ]) {
    final label = '${device.name}${longNames ? ', long names' : ''}';
    testWidgets('no overflows on $label', (tester) async {
      tester.view.physicalSize = Size(device.width, device.height);
      tester.view.devicePixelRatio = device.dpr;
      tester.view.padding = FakeViewPadding(top: 24 * device.dpr);
      tester.platformDispatcher.textScaleFactorTestValue = device.scale;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      final problems = <String>[];
      var where = 'start';
      final original = FlutterError.onError;
      FlutterError.onError = (details) {
        final text = details.toString();
        final headline = text
            .split('\n')
            .firstWhere(
              (l) => l.contains('overflowed') || l.contains('Exception'),
              orElse: () => text.split('\n').first,
            )
            .trim();
        final source = RegExp(
          r'lib[/\\][\w/\\]+\.dart:\d+:\d+',
        ).firstMatch(text)?.group(0);
        problems.add('[$where] $headline  ${source ?? ''}');
      };

      try {
        await _walk(tester, now, longNames: longNames, (w) {
          where = w;
          // Snack bars would cover the buttons the walk taps next.
          messengerKey.currentState?.clearSnackBars();
        });
      } finally {
        FlutterError.onError = original;
        // Shown even if the walk itself fails part-way.
        for (final p in problems.toSet()) {
          // ignore: avoid_print
          print('OVERFLOW $p');
        }
      }

      final unique = problems.toSet().toList();
      expect(unique, isEmpty, reason: '\n${unique.join('\n')}\n');
    });
  }
}

Future<void> _settle(WidgetTester tester, [int ms = 600]) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(Duration(milliseconds: ms ~/ 12));
  }
}

/// Scrolls the main vertical list by [dy], twelve times.
Future<void> _scroll(WidgetTester tester, double dy) async {
  final vertical = find.byWidgetPredicate(
    (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
  );
  if (vertical.evaluate().isEmpty) return;
  for (var i = 0; i < 12; i++) {
    await tester.drag(vertical.first, Offset(0, dy), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 100));
  }
  await _settle(tester, 300);
}

/// Scrolls the main vertical list to the end and back, so every item gets
/// laid out.
Future<void> _scrollThrough(WidgetTester tester) async {
  await _scroll(tester, -400);
  await _scroll(tester, 400);
}

/// Shows or hides a simulated on-screen keyboard, 300dp tall.
Future<void> _keyboard(WidgetTester tester, bool shown) async {
  tester.view.viewInsets = FakeViewPadding(
    bottom: shown ? 300 * tester.view.devicePixelRatio : 0,
  );
  await _settle(tester, 300);
}

Future<void> _closeSheet(WidgetTester tester) async {
  final sheet = find.byType(BottomSheet);
  expect(sheet, findsOneWidget);
  Navigator.of(tester.element(sheet)).pop();
  await _settle(tester, 500);
}

Future<void> _back(WidgetTester tester) async {
  await tester.pageBack();
  await _settle(tester, 600);
}

Future<HuddleStore> _pump(
  WidgetTester tester,
  Snapshot snapshot,
  DateTime now,
) async {
  final store = HuddleStore(MemoryRepository(), snapshot, clock: () => now);
  // Start from scratch so the app picks up the new store's state.
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(HuddleApp(store: store));
  await _settle(tester, 600);
  return store;
}

/// The demo season, optionally with very long squad and player names and
/// three-digit jerseys.
Snapshot _demo(DateTime now, {bool longNames = false}) {
  var s = buildDemoSnapshot(now);
  if (longNames) {
    const squadNames = [
      'Under 14 Boys Development Squad',
      'Senior Girls Elite Performance Group',
    ];
    const surnames = [
      'Montgomery-Fitzgerald',
      'Venkatasubramanian',
      'Bartholomew Richardson',
    ];
    s = Snapshot(
      squads: [
        for (var i = 0; i < s.squads.length; i++)
          s.squads[i].copyWith(name: squadNames[i % squadNames.length]),
      ],
      players: [
        for (var i = 0; i < s.players.length; i++)
          s.players[i].copyWith(
            name:
                'Maximilian${String.fromCharCode(97 + i)} '
                '${surnames[i % surnames.length]}',
            jersey: () => '${100 + i}',
          ),
      ],
      sessions: s.sessions,
      records: s.records,
      settings: s.settings,
    );
  }
  s.settings['onboarded'] = 'true';
  s.settings['coachName'] = 'Coach Alexandra';
  return s;
}

Future<void> _walk(
  WidgetTester tester,
  DateTime now,
  void Function(String) at, {
  required bool longNames,
}) async {
  // --- Onboarding ----------------------------------------------------------
  at('welcome');
  await _pump(tester, Snapshot.empty(), now);
  at('onboarding step 1');
  await tester.tap(find.text('Set up my squad'));
  await _settle(tester);
  await tester.enterText(
    find.widgetWithText(TextField, 'Squad name'),
    'Under 12 Saturday Morning',
  );
  await tester.pump();
  await _scrollThrough(tester);
  await _keyboard(tester, true);
  await _scrollThrough(tester);
  await _keyboard(tester, false);
  at('onboarding step 2');
  await tester.tap(find.text('Next'));
  await _settle(tester);
  await tester.enterText(find.byType(TextField).last, 'Maya\nLeo\nAva');
  await tester.pump();
  await _keyboard(tester, true);
  await _keyboard(tester, false);

  // --- A brand-new squad: empty states -------------------------------------
  at('new squad: today');
  await tester.tap(find.text('Add 3 players'));
  await _settle(tester);
  await _scrollThrough(tester);
  for (final tab in ['Roster', 'History', 'Stats']) {
    at('new squad: $tab');
    await tester.tap(find.text(tab).last);
    await _settle(tester, 800);
    await _scrollThrough(tester);
  }
  at('new squad: roll call');
  await tester.tap(find.text('Today').last);
  await _settle(tester, 800);
  await tester.tap(find.text('Start roll call'));
  await _settle(tester);
  await _scrollThrough(tester);

  // --- Today: hero card ----------------------------------------------------
  at('today');
  final store = await _pump(tester, _demo(now, longNames: longNames), now);
  await _scrollThrough(tester);

  // --- Roll call -----------------------------------------------------------
  at('roll call');
  await tester.tap(find.text('Start roll call'));
  await _settle(tester);
  await _scrollThrough(tester);
  at('roll call: status sheet');
  final squad = store.suggestedSquad()!;
  final first = store.membersOf(squad.id).first;
  await tester.longPress(find.text(first.firstName).first);
  await _settle(tester, 500);
  await tester.tap(find.text('Late').last);
  await _settle(tester, 500);
  at('roll call: marked late');
  await tester.longPress(find.text(first.firstName).first);
  await _settle(tester, 500);
  await _closeSheet(tester);
  at('roll call: search');
  await tester.tap(find.byTooltip('Find player'));
  await _settle(tester, 300);
  await _keyboard(tester, true);
  await _scrollThrough(tester);
  await _keyboard(tester, false);
  at('roll call: add player sheet');
  await tester.tap(find.byTooltip('More'));
  await _settle(tester, 300);
  await tester.tap(find.text('Add a player'));
  await _settle(tester, 500);
  await _keyboard(tester, true);
  await tester.enterText(find.byType(TextField).last, 'Alexander');
  await tester.pump();
  await _keyboard(tester, false);
  await _closeSheet(tester);
  at('roll call: rest are here');
  await tester.tap(find.text('Rest are here'));
  await _settle(tester, 1000);
  await _scrollThrough(tester);

  // --- Session summary (just finished) -------------------------------------
  at('session summary');
  await tester.tap(find.textContaining('Done ·'));
  await _settle(tester, 800);
  await _scrollThrough(tester);
  await tester.tap(find.text('Done').last);
  await _settle(tester, 3000);

  // --- Today: done card ----------------------------------------------------
  at('today: done');
  await _scrollThrough(tester);
  at('session screen');
  await tester.tap(find.text('Summary'));
  await _settle(tester);
  await _scrollThrough(tester);
  await _keyboard(tester, true);
  await _scrollThrough(tester);
  await _keyboard(tester, false);
  at('session: change status');
  await tester.ensureVisible(find.byType(ListTile).first);
  await _settle(tester, 300);
  await tester.tap(find.byType(ListTile).first);
  await _settle(tester, 500);
  await _closeSheet(tester);
  at('session: delete dialog');
  await tester.tap(find.byType(PopupMenuButton<String>).last);
  await _settle(tester, 300);
  await tester.tap(find.text('Delete session'));
  await _settle(tester, 300);
  await tester.tap(find.text('Cancel'));
  await _settle(tester, 300);
  await _back(tester);

  // --- Settings ------------------------------------------------------------
  at('settings');
  await tester.tap(find.byTooltip('Settings'));
  await _settle(tester);
  await _scrollThrough(tester);
  await _keyboard(tester, true);
  await _scrollThrough(tester);
  await _keyboard(tester, false);
  await _back(tester);

  // --- Roster --------------------------------------------------------------
  at('roster');
  await tester.tap(find.text('Roster').last);
  await _settle(tester, 800);
  await _scrollThrough(tester);
  at('roster: player form');
  await tester.tap(find.text('Add player'));
  await _settle(tester, 500);
  await _keyboard(tester, true);
  await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Alexander');
  await tester.pump();
  await _keyboard(tester, false);
  await _closeSheet(tester);
  at('roster: bulk add');
  await tester.tap(find.byTooltip('More').last);
  await _settle(tester, 300);
  await tester.tap(find.text('Add several at once'));
  await _settle(tester, 500);
  await _keyboard(tester, true);
  await _keyboard(tester, false);
  await _closeSheet(tester);

  at('player screen');
  final player = store.players.firstWhere((p) => p.notes.isNotEmpty);
  await tester.ensureVisible(find.text(player.name).first);
  await _settle(tester, 300);
  await tester.tap(find.text(player.name).first);
  await _settle(tester, 800);
  await _scrollThrough(tester);
  at('player: edit');
  await tester.tap(find.byTooltip('Edit'));
  await _settle(tester, 500);
  await _keyboard(tester, true);
  await _keyboard(tester, false);
  await _closeSheet(tester);
  at('player: delete dialog');
  await tester.tap(find.byType(PopupMenuButton<String>).last);
  await _settle(tester, 300);
  await tester.tap(find.text('Delete'));
  await _settle(tester, 300);
  await tester.tap(find.text('Cancel'));
  await _settle(tester, 300);
  await _back(tester);

  at('squads');
  await _scroll(tester, 400);
  await tester.tap(find.byTooltip('Squads'));
  await _settle(tester);
  await _scrollThrough(tester);
  at('squads: edit');
  await tester.tap(find.text(squad.name).first);
  await _settle(tester, 500);
  await _keyboard(tester, true);
  await _keyboard(tester, false);
  await _closeSheet(tester);
  await _back(tester);

  // --- History -------------------------------------------------------------
  at('history');
  await tester.tap(find.text('History').last);
  await _settle(tester, 800);
  await _scrollThrough(tester);
  at('history: log past');
  await tester.tap(find.byTooltip('Log a past session'));
  await _settle(tester, 500);
  await _closeSheet(tester);

  // --- Stats ---------------------------------------------------------------
  for (final period in ['4 weeks', '3 months', 'All time']) {
    at('stats: $period');
    await tester.tap(find.text('Stats').last);
    await _settle(tester, 800);
    await tester.tap(find.text(period));
    await _settle(tester, 800);
    await _scrollThrough(tester);
  }

  // --- Today on a rest day, with a long squad name -------------------------
  at('today: rest day');
  final restDay = now.add(const Duration(days: 1));
  final quiet = _demo(restDay, longNames: longNames);
  await _pump(tester, quiet, restDay);
  await _scrollThrough(tester);
}
