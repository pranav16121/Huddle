import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../data/stats.dart';
import '../format.dart';
import '../scope.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/scoreboard.dart';
import 'roll_call_screen.dart';
import 'session_screen.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  String? _squadId;

  @override
  Widget build(BuildContext context) {
    final store = context.store;
    final squads = store.allSquads;
    if (_squadId != null && store.squad(_squadId!) == null) _squadId = null;
    final sessions = _squadId == null
        ? store.sessions
        : store.sessionsOf(_squadId!);

    // Group by month, newest first.
    final months = <DateTime, List<Session>>{};
    for (final s in sessions) {
      months.putIfAbsent(DateTime(s.date.year, s.date.month), () => []).add(s);
    }

    return SafeArea(
      bottom: false,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: PageTitle(
              'History',
              subtitle: sessions.isEmpty
                  ? null
                  : plural(sessions.length, 'session'),
              actions: [
                if (squads.isNotEmpty)
                  IconButton.filledTonal(
                    tooltip: 'Log a past session',
                    style: IconButton.styleFrom(
                      backgroundColor: context.colors.primaryContainer,
                      foregroundColor: context.colors.onPrimaryContainer,
                    ),
                    onPressed: () => _logPast(context),
                    icon: const Icon(Icons.edit_calendar_outlined),
                  ),
                const SizedBox(width: 8),
              ],
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
          if (sessions.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: const Basketball(size: 64, rotation: 0.3),
                title: 'No sessions yet',
                message:
                    'Every roll call you take shows up here. Forgot one? '
                    'You can log a past session too.',
                action: squads.isEmpty
                    ? null
                    : OutlinedButton.icon(
                        onPressed: () => _logPast(context),
                        icon: const Icon(Icons.edit_calendar_outlined),
                        label: const Text('Log a past session'),
                      ),
              ),
            )
          else
            for (final entry in months.entries) ...[
              SliverToBoxAdapter(
                child: _MonthHeader(
                  month: entry.key,
                  sessions: entry.value,
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverList.separated(
                  itemCount: entry.value.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, i) => SessionTile(
                    session: entry.value[i],
                    showSquad: _squadId == null && squads.length > 1,
                  ),
                ),
              ),
            ],
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }

  Future<void> _logPast(BuildContext context) async {
    final result = await showModalBottomSheet<(String, DateTime)>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _LogPastSheet(initialSquad: _squadId),
    );
    if (result == null || !context.mounted) return;
    await RollCallScreen.open(context, squadId: result.$1, date: result.$2);
  }
}

class _MonthHeader extends StatelessWidget {
  const _MonthHeader({required this.month, required this.sessions});

  final DateTime month;
  final List<Session> sessions;

  @override
  Widget build(BuildContext context) {
    final store = context.store;
    final total = Tally();
    for (final s in sessions) {
      total.addAll(store.tallyOf(s.id));
    }
    return SectionHeader(
      fmtMonth(month),
      trailing: Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Text(
          '${formatRate(total.rate)} attendance',
          style: context.text.labelMedium?.copyWith(
            color: rateColor(total.rate, context.isDark),
          ),
        ),
      ),
    );
  }
}

/// Horizontal squad filter chips ("All" + each squad).
class SquadFilter extends StatelessWidget {
  const SquadFilter({
    super.key,
    required this.squads,
    required this.selected,
    required this.onChanged,
  });

  final List<Squad> squads;
  final String? selected;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
        children: [
          ChoiceChip(
            label: const Text('All squads'),
            selected: selected == null,
            onSelected: (_) => onChanged(null),
          ),
          for (final s in squads) ...[
            const SizedBox(width: 8),
            ChoiceChip(
              avatar: SquadDot(color: context.squadColor(s)),
              label: Text(s.name),
              selected: selected == s.id,
              onSelected: (_) => onChanged(selected == s.id ? null : s.id),
            ),
          ],
        ],
      ),
    );
  }
}

class SessionTile extends StatelessWidget {
  const SessionTile({super.key, required this.session, this.showSquad = true});

  final Session session;
  final bool showSquad;

  @override
  Widget build(BuildContext context) {
    final store = context.store;
    final squad = store.squad(session.squadId);
    final t = store.tallyOf(session.id);
    final today = store.today;
    final isToday = isSameDay(session.date, today);
    final details = [
      '${t.attended} of ${t.total} here',
      if (t.late > 0) '${t.late} late',
      if (t.excused > 0) '${t.excused} excused',
    ].join(' · ');

    return HCard(
      padding: EdgeInsets.zero,
      onTap: () => SessionScreen.open(context, session.id),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 12, 14, 12),
        child: Row(
          children: [
            SizedBox(
              width: 64,
              child: Column(
                children: [
                  Text(
                    '${session.date.day}',
                    style: context.text.headlineMedium?.copyWith(
                      fontSize: 30,
                      height: 1,
                      color: isToday ? Brand.orange : null,
                    ),
                  ),
                  Text(
                    isToday
                        ? 'TODAY'
                        : weekdayShort[session.date.weekday - 1].toUpperCase(),
                    style: context.text.labelSmall?.copyWith(
                      color: isToday ? Brand.orange : null,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: 1,
              height: 44,
              color: context.colors.outlineVariant,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (showSquad && squad != null) ...[
                    SquadTag(squad: squad),
                    const SizedBox(height: 5),
                  ],
                  Text(
                    details,
                    style: context.text.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (session.note.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      session.note,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.bodySmall,
                    ),
                  ],
                  const SizedBox(height: 8),
                  _MiniBar(tally: t),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Text(
              formatRate(t.rate),
              style: context.text.headlineSmall?.copyWith(
                color: rateColor(t.rate, context.isDark),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniBar extends StatelessWidget {
  const _MiniBar({required this.tally});

  final Tally tally;

  @override
  Widget build(BuildContext context) {
    final total = tally.total;
    if (total == 0) return const SizedBox.shrink();
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: SizedBox(
        height: 5,
        child: Row(
          children: [
            for (final s in AttendanceStatus.values)
              if (tally.count(s) > 0)
                Expanded(
                  flex: tally.count(s),
                  child: Container(
                    color: s == AttendanceStatus.absent
                        ? context.colors.surfaceContainerHigh
                        : context.statusColor(s),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _LogPastSheet extends StatefulWidget {
  const _LogPastSheet({this.initialSquad});

  final String? initialSquad;

  @override
  State<_LogPastSheet> createState() => _LogPastSheetState();
}

class _LogPastSheetState extends State<_LogPastSheet> {
  String? _squadId;
  DateTime? _date;

  @override
  Widget build(BuildContext context) {
    final store = context.store;
    final squads = store.squads;
    _squadId ??= widget.initialSquad ?? (squads.isEmpty ? null : squads.first.id);
    final today = store.today;
    _date ??= today.subtract(const Duration(days: 1));
    final date = _date!;
    final existing = _squadId == null
        ? const <Session>[]
        : store.sessionsOn(date, squadId: _squadId);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Log a past session', style: context.text.headlineSmall),
            const SizedBox(height: 4),
            Text(
              'For the days you took attendance on paper, or forgot.',
              style: context.text.bodySmall,
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in squads)
                  ChoiceChip(
                    avatar: SquadDot(color: context.squadColor(s)),
                    label: Text(s.name),
                    selected: s.id == _squadId,
                    onSelected: (_) => setState(() => _squadId = s.id),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(alignment: Alignment.centerLeft),
              onPressed: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: date,
                  firstDate: DateTime(today.year - 3),
                  lastDate: today,
                );
                if (picked != null) setState(() => _date = dateOnly(picked));
              },
              icon: const Icon(Icons.calendar_today_outlined),
              label: Text(fmtLong(date)),
            ),
            if (existing.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                'There\'s already a session that day — you\'ll edit it.',
                style: context.text.bodySmall,
              ),
            ],
            const SizedBox(height: 18),
            FilledButton(
              onPressed: _squadId == null
                  ? null
                  : () => Navigator.pop(context, (_squadId!, date)),
              child: Text(existing.isEmpty ? 'Take roll call' : 'Edit session'),
            ),
          ],
        ),
      ),
    );
  }
}
