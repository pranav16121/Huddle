import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../data/stats.dart';
import '../format.dart';
import '../scope.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/rate_bars.dart';
import '../widgets/scoreboard.dart';
import 'history_screen.dart' show SquadFilter;
import 'player_screen.dart';

enum _Period {
  month('4 weeks', 28),
  quarter('3 months', 91),
  all('All time', null);

  const _Period(this.label, this.days);

  final String label;
  final int? days;
}

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  _Period _period = _Period.month;
  String? _squadId;

  @override
  Widget build(BuildContext context) {
    final store = context.store;
    final squads = store.allSquads;
    if (_squadId != null && store.squad(_squadId!) == null) _squadId = null;
    final today = store.today;
    final since = _period.days == null
        ? null
        : today.subtract(Duration(days: _period.days! - 1));
    final ov = store.overview(since: since, squadId: _squadId);

    // Per-player tallies within the selected period and squad.
    final perPlayer = <String, Tally>{};
    for (final s in ov.sessions) {
      for (final r in store.recordsOf(s.id).values) {
        perPlayer.putIfAbsent(r.playerId, Tally.new).add(r.status);
      }
    }
    final players = store.players
        .where((p) => _squadId == null || p.squadIds.contains(_squadId))
        .toList();
    Tally t(Player p) => perPlayer[p.id] ?? Tally();

    final reliable = players.where((p) => t(p).counted >= 3).toList()
      ..sort((a, b) {
        final byRate = (t(b).rate ?? 0).compareTo(t(a).rate ?? 0);
        return byRate != 0 ? byRate : t(b).attended.compareTo(t(a).attended);
      });
    final streaks =
        players.where((p) => store.statsOf(p.id).currentStreak >= 2).toList()
          ..sort(
            (a, b) => store
                .statsOf(b.id)
                .currentStreak
                .compareTo(store.statsOf(a.id).currentStreak),
          );
    final oftenLate = players.where((p) => t(p).late >= 2).toList()
      ..sort((a, b) => t(b).late.compareTo(t(a).late));
    final nudges =
        players
            .where(
              (p) =>
                  store.statsOf(p.id).missedInARow >= 2 ||
                  (t(p).counted >= 3 && (t(p).rate ?? 1) < 0.6),
            )
            .toList()
          ..sort((a, b) => (t(a).rate ?? 1).compareTo(t(b).rate ?? 1));

    final recent = ov.sessions.length > 30
        ? ov.sessions.sublist(ov.sessions.length - 30)
        : ov.sessions;

    return SafeArea(
      bottom: false,
      child: CustomScrollView(
        slivers: [
          const SliverToBoxAdapter(child: PageTitle('Stats')),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            sliver: SliverToBoxAdapter(
              child: SegmentedButton<_Period>(
                showSelectedIcon: false,
                segments: [
                  for (final p in _Period.values)
                    ButtonSegment(value: p, label: Text(p.label)),
                ],
                selected: {_period},
                onSelectionChanged: (s) => setState(() => _period = s.first),
              ),
            ),
          ),
          if (squads.length > 1)
            SliverToBoxAdapter(
              child: SquadFilter(
                squads: squads,
                selected: _squadId,
                onChanged: (id) => setState(() => _squadId = id),
              ),
            ),
          if (ov.sessions.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: const Basketball(size: 64, rotation: 0.8),
                title: 'No sessions in this period',
                message: store.sessions.isEmpty
                    ? 'Take your first roll call and the numbers will start '
                          'rolling in.'
                    : 'Try a longer period to see more.',
              ),
            )
          else ...[
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  // Padding, plus the number and label, which grow with the
                  // phone's font size.
                  mainAxisExtent:
                      46 + MediaQuery.textScalerOf(context).scale(52),
                ),
                delegate: SliverChildListDelegate([
                  StatTile(
                    value: formatRate(ov.rate),
                    label: 'Attendance',
                    color: rateColor(ov.rate, context.isDark),
                  ),
                  StatTile(
                    value: '${ov.sessions.length}',
                    label: ov.sessions.length == 1 ? 'Session' : 'Sessions',
                  ),
                  StatTile(
                    value: ov.averageTurnout == null
                        ? '–'
                        : ov.averageTurnout!.toStringAsFixed(1),
                    label: 'Players per session',
                  ),
                  StatTile(
                    value: '${ov.fullHouses}',
                    label: ov.fullHouses == 1 ? 'Full house' : 'Full houses',
                    icon: ov.fullHouses > 0 ? Icons.celebration_outlined : null,
                    color: ov.fullHouses > 0 ? Brand.orange : null,
                  ),
                ]),
              ),
            ),
            SliverToBoxAdapter(
              child: SectionHeader(
                recent.length < ov.sessions.length
                    ? 'Turnout · last ${recent.length} sessions'
                    : 'Turnout by session',
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverToBoxAdapter(
                child: HCard(
                  child: RateBars(
                    average: ov.rate,
                    data: [
                      for (final s in recent)
                        _bar(s, store.tallyOf(s.id), store.squad(s.squadId)),
                    ],
                  ),
                ),
              ),
            ),
            if (reliable.isNotEmpty)
              ..._board(
                context,
                'Most reliable',
                reliable.take(5).toList(),
                (p) => formatRate(t(p).rate),
                (p) => '${t(p).attended} of ${t(p).counted} sessions',
                (p) => rateColor(t(p).rate, context.isDark),
              ),
            if (streaks.isNotEmpty)
              ..._board(
                context,
                'Longest current streaks',
                streaks.take(5).toList(),
                (p) => '${store.statsOf(p.id).currentStreak}',
                (p) => 'Best ever: ${store.statsOf(p.id).bestStreak}',
                (_) => Brand.orange,
                icon: Icons.local_fire_department,
              ),
            if (oftenLate.isNotEmpty)
              ..._board(
                context,
                'Often late',
                oftenLate.take(3).toList(),
                (p) => '${t(p).late}×',
                (p) =>
                    'Late in ${t(p).late} of ${t(p).attended} sessions attended',
                (_) => context.statusColor(AttendanceStatus.late),
              ),
            if (nudges.isNotEmpty)
              ..._board(
                context,
                'Could use a nudge',
                nudges.take(5).toList(),
                (p) => formatRate(t(p).rate),
                (p) {
                  final missed = store.statsOf(p.id).missedInARow;
                  return missed >= 2
                      ? 'Missed the last $missed sessions'
                      : '${t(p).absent} missed this period';
                },
                (p) => rateColor(t(p).rate, context.isDark),
              ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              sliver: SliverToBoxAdapter(
                child: Text(
                  'Attendance = here + late, out of everyone expected. '
                  'Excused absences don\'t count against anyone.',
                  style: context.text.bodySmall,
                ),
              ),
            ),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }

  BarDatum _bar(Session s, Tally t, Squad? squad) => BarDatum(
    value: t.rate,
    label: fmtShort(s.date),
    caption:
        '${fmtShort(s.date)}${_squadId == null && squad != null ? ' · ${squad.name}' : ''}'
        ' · ${t.attended}/${t.total} · ${formatRate(t.rate)}',
  );

  List<Widget> _board(
    BuildContext context,
    String title,
    List<Player> players,
    String Function(Player) value,
    String Function(Player) detail,
    Color Function(Player) color, {
    IconData? icon,
  }) {
    return [
      SliverToBoxAdapter(child: SectionHeader(title)),
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: SliverToBoxAdapter(
          child: Card(
            child: Column(
              children: [
                for (var i = 0; i < players.length; i++)
                  ListTile(
                    onTap: () => PlayerScreen.open(context, players[i].id),
                    leading: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 22,
                          child: Text(
                            '${i + 1}',
                            style: context.text.titleMedium?.copyWith(
                              fontFamily: Brand.display,
                              fontWeight: FontWeight.w800,
                              color: context.colors.onSurfaceVariant,
                            ),
                          ),
                        ),
                        PlayerAvatar(
                          player: players[i],
                          size: 38,
                          showJersey: false,
                        ),
                      ],
                    ),
                    title: Text(players[i].name),
                    subtitle: Text(detail(players[i])),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (icon != null)
                          Icon(icon, size: 18, color: color(players[i])),
                        Text(
                          value(players[i]),
                          style: context.text.headlineSmall?.copyWith(
                            fontSize: 22,
                            color: color(players[i]),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    ];
  }
}
