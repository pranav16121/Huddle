import 'dart:math';

import 'package:attendance/data/models.dart';

/// Builds a realistic sample season (two squads, ~10 weeks of sessions) for
/// tests. Ids start with "demo-", like the demo that older versions shipped.
Snapshot buildDemoSnapshot(DateTime now) {
  final today = dateOnly(now);
  final rng = Random(7);
  final created = today.subtract(const Duration(days: 80));

  int wd(int offset) => ((today.weekday - 1 + offset) % 7) + 1;

  // Juniors always train today, so there's a live roll call to try.
  final juniors = Squad(
    id: 'demo-juniors',
    name: 'Junior Hoopers',
    colorIndex: 0,
    weekdays: {wd(0), wd(-3)},
    startMinutes: ((now.hour + 1).clamp(6, 21)) * 60,
    createdAt: created,
  );
  final stars = Squad(
    id: 'demo-stars',
    name: 'Rising Stars',
    colorIndex: 1,
    weekdays: {wd(-1), wd(-5)},
    startMinutes: 10 * 60,
    createdAt: created.add(const Duration(minutes: 1)),
  );

  // name, jersey, reliability (chance of showing up), lateness, notes
  const juniorKids = [
    ('Aarav Mehta', '7', 0.92, 0.10, ''),
    ('Maya Rodriguez', '23', 1.0, 0.0, 'Left-handed shooter'),
    ('Leo Kim', '4', 0.85, 0.25, ''),
    ('Zara Khan', '11', 0.90, 0.05, 'Asthma: inhaler in the blue bag'),
    ('Ishaan Gupta', null, 0.78, 0.15, ''),
    ('Ava Thompson', '3', 0.95, 0.05, ''),
    ('Kabir Singh', '9', 0.88, 0.20, 'Mum picks up at 6'),
    ('Noah Williams', null, 0.70, 0.10, ''),
    ('Anaya Iyer', '15', 0.93, 0.0, ''),
    ('Ethan Brooks', '21', 0.80, 0.30, ''),
    ('Riya Patel', '8', 0.60, 0.05, ''), // drifting away: nudge candidate
    ('Arjun Nair', '12', 0.90, 0.10, ''),
    ('Sara Fernandes', null, 0.97, 0.0, ''),
  ];
  const starKids = [
    ('Vihaan Rao', '5', 0.95, 0.05, 'Team captain'),
    ('Chloe Martin', '14', 0.88, 0.10, ''),
    ('Aditya Joshi', '30', 0.85, 0.20, ''),
    ('Mia Chen', '2', 0.98, 0.0, ''),
    ('Rohan Das', null, 0.75, 0.15, ''),
    ('Tara Menon', '10', 0.92, 0.05, ''),
    ('Dev Malhotra', '33', 0.82, 0.25, ''),
    ('Emma Wilson', '6', 0.90, 0.05, 'Knee brace for scrimmages'),
    ('Kiara D\'Souza', null, 0.87, 0.10, ''),
    ('Samuel Lee', '24', 0.93, 0.0, ''),
  ];

  final players = <Player>[];
  final traits = <String, (double, double)>{};
  void addKids(
    List<(String, String?, double, double, String)> kids,
    Squad squad,
  ) {
    for (var i = 0; i < kids.length; i++) {
      final (name, jersey, reliability, lateness, notes) = kids[i];
      final id = 'demo-${squad.id.substring(5)}-$i';
      players.add(
        Player(
          id: id,
          name: name,
          jersey: jersey,
          squadIds: {squad.id},
          notes: notes,
          createdAt: created.add(Duration(seconds: players.length)),
        ),
      );
      traits[id] = (reliability, lateness);
    }
  }

  addKids(juniorKids, juniors);
  addKids(starKids, stars);

  // Aarav also trains with the older group.
  final aarav = players.first;
  players[0] = aarav.copyWith(squadIds: {juniors.id, stars.id});

  const notes = [
    'Layup lines & 3-man weave',
    'Free-throw challenge',
    'Scrimmage day',
    'Defensive slides and closeouts',
    'Dribble relay races',
    'Passing: chest, bounce, overhead',
    '',
    '',
    '',
  ];

  final sessions = <Session>[];
  final records = <AttendanceRecord>[];
  for (final squad in [juniors, stars]) {
    final members = players.where((p) => p.squadIds.contains(squad.id));
    final days = [
      for (var d = 70; d >= 1; d--) today.subtract(Duration(days: d)),
    ].where(squad.trainsOn).toList();

    for (var i = 0; i < days.length; i++) {
      final day = days[i];
      final weeksAgo = today.difference(day).inDays / 7;
      final session = Session(
        id: 'demo-s-${squad.id.substring(5)}-$i',
        squadId: squad.id,
        date: day,
        createdAt: day.add(
          Duration(minutes: (squad.startMinutes ?? 600) + rng.nextInt(10)),
        ),
        note: notes[rng.nextInt(notes.length)],
      );
      sessions.add(session);
      // One rainy-day session with a small turnout.
      final rainy = squad == juniors && i == days.length ~/ 2;

      for (final p in members) {
        var (reliability, lateness) = traits[p.id]!;
        // Riya has missed the last few weeks: a gentle nudge for the coach.
        final drifting = p.name.startsWith('Riya') && weeksAgo < 1.5;
        if (rainy) reliability *= 0.5;
        final roll = rng.nextDouble();
        final AttendanceStatus status;
        if (drifting) {
          status = AttendanceStatus.absent;
        } else if (roll < reliability) {
          status = rng.nextDouble() < lateness
              ? AttendanceStatus.late
              : AttendanceStatus.present;
        } else {
          status = rng.nextDouble() < 0.35 && !rainy
              ? AttendanceStatus.excused
              : AttendanceStatus.absent;
        }
        records.add(
          AttendanceRecord(
            sessionId: session.id,
            playerId: p.id,
            status: status,
            updatedAt: session.createdAt.add(
              Duration(minutes: status == AttendanceStatus.late ? 12 : 1),
            ),
          ),
        );
      }
    }
  }

  return Snapshot(
    squads: [juniors, stars],
    players: players,
    sessions: sessions,
    records: records,
    settings: {'demo': 'true'},
  );
}
