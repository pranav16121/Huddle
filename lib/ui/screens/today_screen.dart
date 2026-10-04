import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../data/stats.dart';
import '../../data/store.dart';
import '../format.dart';
import '../scope.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/scoreboard.dart';
import 'player_screen.dart';
import 'roll_call_screen.dart';
import 'session_screen.dart';
import 'settings_screen.dart';
import 'squads_screen.dart';

class TodayScreen extends StatelessWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.store;
    final now = store.now;
    final squads = store.squads;
    final hero = store.suggestedSquad() ?? (squads.length == 1 ? squads.first : null);
    final alsoToday = squads
        .where((s) => s.trainsOn(now) && s.id != hero?.id)
        .toList();
    final others = squads
        .where((s) => !s.trainsOn(now) && s.id != hero?.id)
        .toList();
    final name = store.coachName;

    return SafeArea(
      bottom: false,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 8, 14),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${greeting(now)}${name.isEmpty ? '' : ', $name'}'
                              .toUpperCase(),
                          style: context.text.labelSmall?.copyWith(
                            color: context.isDark
                                ? const Color(0xFFFF9A5C)
                                : Brand.orangeDeep,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          fmtLong(now),
                          style: context.text.displaySmall?.copyWith(
                            fontSize: 34,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Settings',
                    icon: const Icon(Icons.settings_outlined),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const SettingsScreen(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverToBoxAdapter(
              child: squads.isEmpty
                  ? const _NoSquadsCard()
                  : hero == null
                  ? const _RestDayCard()
                  : _HeroCard(squad: hero),
            ),
          ),
          if (alsoToday.isNotEmpty) ...[
            const SliverToBoxAdapter(child: SectionHeader('Also today')),
            _SquadList(squads: alsoToday),
          ],
          if (others.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: SectionHeader(
                hero == null || !hero.trainsOn(now)
                    ? 'Your squads'
                    : 'Not on today\'s schedule',
              ),
            ),
            _SquadList(squads: others),
          ],
          ..._insights(context, store),
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }

  List<Widget> _insights(BuildContext context, HuddleStore store) {
    if (store.sessions.isEmpty) {
      return [
        const SliverToBoxAdapter(child: SectionHeader('Insights')),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverToBoxAdapter(
            child: HCard(
              child: Row(
                children: [
                  const Icon(Icons.insights_outlined, size: 28),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      'Streaks, trends and who might need a nudge will show '
                      'up here after your first few sessions.',
                      style: context.text.bodyMedium?.copyWith(height: 1.35),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ];
    }

    final players = store.players;
    final nudges = players
        .where((p) => store.statsOf(p.id).missedInARow >= 2)
        .toList()
      ..sort(
        (a, b) => store
            .statsOf(b.id)
            .missedInARow
            .compareTo(store.statsOf(a.id).missedInARow),
      );
    final onFire = players
        .where((p) => store.statsOf(p.id).currentStreak >= 4)
        .toList()
      ..sort(
        (a, b) => store
            .statsOf(b.id)
            .currentStreak
            .compareTo(store.statsOf(a.id).currentStreak),
      );

    return [
      const SliverToBoxAdapter(child: SectionHeader('This week')),
      const SliverPadding(
        padding: EdgeInsets.symmetric(horizontal: 16),
        sliver: SliverToBoxAdapter(child: _WeekCard()),
      ),
      if (nudges.isNotEmpty) ...[
        SliverToBoxAdapter(
          child: SectionHeader(
            'Might need a nudge',
            trailing: Text(
              '${nudges.length}',
              style: context.text.labelMedium,
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverToBoxAdapter(
            child: Card(
              child: Column(
                children: [
                  for (final p in nudges.take(4))
                    _NudgeRow(player: p, stats: store.statsOf(p.id)),
                ],
              ),
            ),
          ),
        ),
      ],
      if (onFire.isNotEmpty) ...[
        const SliverToBoxAdapter(child: SectionHeader('On fire')),
        SliverToBoxAdapter(
          child: SizedBox(
            height: 112,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: onFire.length.clamp(0, 10),
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (context, i) => _StreakChip(
                player: onFire[i],
                streak: store.statsOf(onFire[i].id).currentStreak,
              ),
            ),
          ),
        ),
      ],
    ];
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.squad});

  final Squad squad;

  @override
  Widget build(BuildContext context) {
    final store = context.store;
    final now = store.now;
    final members = store.membersOf(squad.id);
    final done = store.sessionsOn(now, squadId: squad.id);
    final scheduled = squad.trainsOn(now);
    final start = squad.startMinutes;

    if (done.isNotEmpty) {
      return _DoneCard(squad: squad, session: done.first);
    }

    final label = !scheduled
        ? 'NOT ON TODAY\'S SCHEDULE'
        : start != null
        ? '${(now.hour * 60 + now.minute) > start ? 'STARTED' : 'UP NEXT'} · '
              '${fmtMinutes(context, start).toUpperCase()}'
        : 'TRAINING TODAY';

    return Pressable(
      scale: 0.98,
      onTap: () => RollCallScreen.open(context, squadId: squad.id),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFF8A3D), Brand.orange, Color(0xFFD14E08)],
          ),
          boxShadow: [
            BoxShadow(
              color: Brand.orange.withValues(alpha: 0.35),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: CourtLinesPainter(
                  color: Colors.white.withValues(alpha: 0.13),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontFamily: Brand.display,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      letterSpacing: 1.8,
                      color: Colors.white70,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    squad.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: Brand.display,
                      fontWeight: FontWeight.w800,
                      fontSize: 40,
                      height: 1,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      _AvatarStack(players: members),
                      const SizedBox(width: 10),
                      Text(
                        members.isEmpty
                            ? 'No players yet'
                            : plural(members.length, 'player'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Container(
                    height: 58,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: const Row(
                      children: [
                        Icon(
                          Icons.sports_basketball,
                          color: Brand.orangeDeep,
                          size: 26,
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Start roll call',
                            style: TextStyle(
                              fontFamily: Brand.body,
                              fontWeight: FontWeight.w800,
                              fontSize: 18,
                              color: Brand.ink,
                            ),
                          ),
                        ),
                        Icon(Icons.arrow_forward_rounded, color: Brand.ink),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DoneCard extends StatelessWidget {
  const _DoneCard({required this.squad, required this.session});

  final Squad squad;
  final Session session;

  @override
  Widget build(BuildContext context) {
    final store = context.store;
    final tally = store.tallyOf(session.id);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Brand.board,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: CourtLinesPainter(
                color: Colors.white.withValues(alpha: 0.06),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(
                      Icons.check_circle,
                      color: Color(0xFF4DFFA0),
                      size: 18,
                    ),
                    SizedBox(width: 6),
                    Text(
                      'ROLL CALL DONE',
                      style: TextStyle(
                        fontFamily: Brand.display,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        letterSpacing: 1.8,
                        color: Color(0xFF9AA0B2),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  squad.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: Brand.display,
                    fontWeight: FontWeight.w800,
                    fontSize: 36,
                    height: 1,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    LedNumber(
                      value: tally.attended,
                      digits: tally.total >= 100 ? 3 : 2,
                      height: 40,
                      color: const Color(0xFF4DFFA0),
                    ),
                    const SizedBox(width: 10),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        'of ${tally.total} here'
                        '${tally.late > 0 ? '\n${tally.late} late' : ''}',
                        style: const TextStyle(
                          color: Color(0xFFB8BDCC),
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                          height: 1.25,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Color(0xFF3A3F4E)),
                          minimumSize: const Size(0, 50),
                        ),
                        onPressed: () =>
                            SessionScreen.open(context, session.id),
                        child: const Text('Summary'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 50),
                        ),
                        onPressed: () =>
                            RollCallScreen.edit(context, session.id),
                        child: const Text('Update'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AvatarStack extends StatelessWidget {
  const _AvatarStack({required this.players});

  final List<Player> players;

  @override
  Widget build(BuildContext context) {
    final shown = players.take(5).toList();
    if (shown.isEmpty) {
      return const Icon(Icons.group_add_outlined, color: Colors.white);
    }
    const size = 32.0;
    return SizedBox(
      width: size + (shown.length - 1) * (size * 0.62),
      height: size,
      child: Stack(
        children: [
          for (var i = 0; i < shown.length; i++)
            Positioned(
              left: i * size * 0.62,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Brand.orange, width: 2),
                ),
                child: PlayerAvatar(
                  player: shown[i],
                  size: size - 4,
                  showJersey: false,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RestDayCard extends StatelessWidget {
  const _RestDayCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Brand.board,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: CourtLinesPainter(
                color: Colors.white.withValues(alpha: 0.06),
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(22, 22, 22, 22),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'REST DAY',
                        style: TextStyle(
                          fontFamily: Brand.display,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          letterSpacing: 1.8,
                          color: Color(0xFF9AA0B2),
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        'No training on the schedule today',
                        style: TextStyle(
                          fontFamily: Brand.display,
                          fontWeight: FontWeight.w800,
                          fontSize: 28,
                          height: 1.05,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Extra session? Pick a squad below to take roll call.',
                        style: TextStyle(
                          color: Color(0xFFB8BDCC),
                          fontSize: 14.5,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 12),
                Basketball(size: 64, rotation: 0.4),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NoSquadsCard extends StatelessWidget {
  const _NoSquadsCard();

  @override
  Widget build(BuildContext context) {
    return HCard(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Basketball(size: 48),
          const SizedBox(height: 14),
          Text('Create a squad', style: context.text.headlineMedium),
          const SizedBox(height: 6),
          Text(
            'A squad is a group you coach, like "U10 Saturday". Add one to '
            'start taking roll call.',
            style: context.text.bodyMedium?.copyWith(height: 1.35),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: () => SquadForm.open(context),
            icon: const Icon(Icons.add),
            label: const Text('New squad'),
          ),
        ],
      ),
    );
  }
}

class _SquadList extends StatelessWidget {
  const _SquadList({required this.squads});

  final List<Squad> squads;

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverList.separated(
        itemCount: squads.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, i) => _SquadRow(squad: squads[i]),
      ),
    );
  }
}

class _SquadRow extends StatelessWidget {
  const _SquadRow({required this.squad});

  final Squad squad;

  @override
  Widget build(BuildContext context) {
    final store = context.store;
    final members = store.membersOf(squad.id).length;
    final done = store.sessionsOn(store.now, squadId: squad.id);
    final tally = done.isEmpty ? null : store.tallyOf(done.first.id);
    final start = squad.startMinutes;
    final details = [
      fmtWeekdays(squad.weekdays),
      if (start != null) fmtMinutes(context, start),
      plural(members, 'player'),
    ].join(' · ');

    return HCard(
      padding: EdgeInsets.zero,
      onTap: () => done.isEmpty
          ? RollCallScreen.open(context, squadId: squad.id)
          : SessionScreen.open(context, done.first.id),
      child: IntrinsicHeight(
        child: Row(
          children: [
            Container(width: 6, color: context.squadColor(squad)),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 8, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(squad.name, style: context.text.titleMedium),
                    const SizedBox(height: 2),
                    Text(details, style: context.text.bodySmall),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: tally != null
                  ? Row(
                      children: [
                        Icon(
                          Icons.check_circle,
                          size: 18,
                          color: context.statusColor(AttendanceStatus.present),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${tally.attended}/${tally.total}',
                          style: context.text.titleMedium,
                        ),
                      ],
                    )
                  : FilledButton.tonal(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 42),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        backgroundColor: context.colors.primaryContainer,
                        foregroundColor: context.colors.onPrimaryContainer,
                      ),
                      onPressed: () =>
                          RollCallScreen.open(context, squadId: squad.id),
                      child: const Text('Start'),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WeekCard extends StatelessWidget {
  const _WeekCard();

  @override
  Widget build(BuildContext context) {
    final store = context.store;
    final today = store.today;
    final monday = today.subtract(Duration(days: today.weekday - 1));
    final week = store.overview(since: monday);
    final byDay = <int, Tally>{};
    for (final s in week.sessions) {
      byDay.putIfAbsent(s.date.weekday, Tally.new).addAll(store.tallyOf(s.id));
    }
    final rate = week.rate;

    return HCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              for (var d = 1; d <= 7; d++)
                Expanded(
                  child: _DayDot(
                    letter: weekdayLetters[d - 1],
                    tally: byDay[d],
                    isToday: d == today.weekday,
                    isFuture: d > today.weekday,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            week.sessions.isEmpty
                ? 'No sessions yet this week'
                : '${plural(week.sessions.length, 'session')} · '
                      '${formatRate(rate)} attendance · '
                      '${plural(week.total.attended, 'check-in')}',
            style: context.text.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _DayDot extends StatelessWidget {
  const _DayDot({
    required this.letter,
    required this.tally,
    required this.isToday,
    required this.isFuture,
  });

  final String letter;
  final Tally? tally;
  final bool isToday;
  final bool isFuture;

  @override
  Widget build(BuildContext context) {
    final t = tally;
    final color = t == null ? null : rateColor(t.rate, context.isDark);
    return Column(
      children: [
        Text(
          letter,
          style: context.text.labelMedium?.copyWith(
            color: isToday ? context.colors.onSurface : null,
            fontWeight: isToday ? FontWeight.w800 : null,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color?.withValues(alpha: context.isDark ? 0.25 : 0.16),
            border: Border.all(
              color: isToday
                  ? Brand.orange
                  : color ?? context.colors.outlineVariant,
              width: isToday ? 2 : 1.5,
            ),
          ),
          child: t == null
              ? (isFuture
                    ? null
                    : Icon(
                        Icons.remove,
                        size: 14,
                        color: context.colors.outlineVariant,
                      ))
              : Text(
                  '${t.attended}',
                  style: TextStyle(
                    fontFamily: Brand.display,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: color,
                  ),
                ),
        ),
      ],
    );
  }
}

class _NudgeRow extends StatelessWidget {
  const _NudgeRow({required this.player, required this.stats});

  final Player player;
  final PlayerStats stats;

  @override
  Widget build(BuildContext context) {
    final store = context.store;
    final last = stats.lastAttended;
    return ListTile(
      onTap: () => PlayerScreen.open(context, player.id),
      leading: PlayerAvatar(player: player, size: 42),
      title: Text(player.name),
      subtitle: Text(
        'Missed ${stats.missedInARow} in a row · '
        '${last == null ? 'not seen yet' : 'last here ${fmtRelativeInline(last, store.today)}'}',
      ),
      trailing: FormGuide(newestFirst: stats.recent, count: 5, dot: 8),
    );
  }
}

class _StreakChip extends StatelessWidget {
  const _StreakChip({required this.player, required this.streak});

  final Player player;
  final int streak;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: () => PlayerScreen.open(context, player.id),
      child: Container(
        width: 92,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
        decoration: BoxDecoration(
          color: context.colors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: context.colors.outlineVariant),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                PlayerAvatar(player: player, size: 44, showJersey: false),
                Positioned(
                  right: -10,
                  bottom: -6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: Brand.orange,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: context.colors.surfaceContainerLowest,
                        width: 2,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.local_fire_department,
                          size: 12,
                          color: Colors.white,
                        ),
                        Text(
                          '$streak',
                          style: const TextStyle(
                            fontFamily: Brand.display,
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              player.firstName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.text.titleSmall,
            ),
          ],
        ),
      ),
    );
  }
}
