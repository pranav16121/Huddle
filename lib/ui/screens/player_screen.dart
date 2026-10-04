import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/models.dart';
import '../../data/stats.dart';
import '../format.dart';
import '../scope.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/rate_bars.dart';
import 'roll_call_screen.dart' show StatusSheet;
import 'roster_screen.dart' show PlayerForm;

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key, required this.playerId});

  final String playerId;

  static Future<void> open(BuildContext context, String playerId) =>
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => PlayerScreen(playerId: playerId)),
      );

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  bool _showAll = false;

  Future<void> _delete(Player p) async {
    final store = context.readStore;
    final sessions = store.historyOf(p.id).length;
    final ok = await confirm(
      context,
      title: 'Delete ${p.firstName}?',
      message: sessions == 0
          ? '${p.name} will be removed from your roster.'
          : '${p.name} and their attendance in ${plural(sessions, 'session')} '
                'will be permanently deleted. If they\'ve just stopped '
                'coming, archive them instead to keep the history.',
      action: 'Delete',
      destructive: true,
    );
    if (!ok || !mounted) return;
    Navigator.of(context).pop();
    store.deletePlayer(p.id);
  }

  void _archive(Player p, bool archived) {
    final store = context.readStore;
    store.setPlayerArchived(p.id, archived);
    showSnack(
      context,
      archived ? '${p.firstName} archived' : '${p.firstName} is back on the roster',
      actionLabel: 'Undo',
      onAction: () => store.setPlayerArchived(p.id, !archived),
    );
  }

  Future<void> _changeStatus(Player p, HistoryEntry e) async {
    final store = context.readStore;
    final squad = store.squad(e.session.squadId);
    final result = await showModalBottomSheet<Object>(
      context: context,
      // Lets the sheet grow past half the screen with large text.
      isScrollControlled: true,
      builder: (_) => StatusSheet(
        player: p,
        current: e.record.status,
        canRemove: true,
        subtitle: '${squad?.name ?? 'Session'} · ${fmtShort(e.session.date)}',
      ),
    );
    if (!mounted) return;
    if (result is AttendanceStatus) {
      store.setStatus(e.session.id, p.id, result);
    } else if (result == StatusSheet.remove) {
      store.removeFromSession(e.session.id, p.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.store;
    final p = store.player(widget.playerId);
    if (p == null) return const Scaffold();
    final stats = store.statsOf(p.id);
    final history = store.historyOf(p.id);
    final squads = p.squadIds.map(store.squad).whereType<Squad>().toList();
    final months = monthlyTallies(history, now: store.today);
    final shownHistory = _showAll ? history : history.take(12).toList();

    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            tooltip: 'Edit',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => PlayerForm.open(context, player: p),
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              switch (v) {
                case 'archive':
                  _archive(p, !p.archived);
                case 'delete':
                  _delete(p);
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'archive',
                child: Text(p.archived ? 'Restore to roster' : 'Archive'),
              ),
              const PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          Center(
            child: PlayerAvatar(
              player: p,
              size: 96,
              heroTag: 'avatar-${p.id}',
            ),
          ),
          const SizedBox(height: 14),
          Text(
            p.name,
            textAlign: TextAlign.center,
            style: context.text.headlineLarge,
          ),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 6,
            runSpacing: 6,
            children: [
              if (p.archived)
                Chip(
                  label: const Text('Archived'),
                  visualDensity: VisualDensity.compact,
                  side: BorderSide(color: context.colors.outlineVariant),
                ),
              for (final s in squads) SquadTag(squad: s),
            ],
          ),
          const SizedBox(height: 22),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: HCard(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  RateRing(rate: stats.rate, size: 112, stroke: 12),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _BigStat(
                          icon: Icons.local_fire_department,
                          iconColor: Brand.orange,
                          value: '${stats.currentStreak}',
                          label: 'in a row',
                        ),
                        const SizedBox(height: 10),
                        _BigStat(
                          icon: Icons.emoji_events_outlined,
                          iconColor: const Color(0xFFD99A0B),
                          value: '${stats.bestStreak}',
                          label: 'best streak',
                        ),
                        const SizedBox(height: 10),
                        _BigStat(
                          icon: Icons.event_available_outlined,
                          iconColor: context.statusColor(
                            AttendanceStatus.present,
                          ),
                          value: '${stats.tally.attended}',
                          label: 'of ${stats.tally.counted} attended',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                for (final s in AttendanceStatus.values) ...[
                  Expanded(
                    child: _MiniCount(status: s, count: stats.tally.count(s)),
                  ),
                  if (s != AttendanceStatus.absent) const SizedBox(width: 8),
                ],
              ],
            ),
          ),
          if (history.isNotEmpty) ...[
            const SectionHeader('Form · last 10'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: HCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Shrinks on narrow phones rather than running off
                    // the card.
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: FormGuide(
                        newestFirst: stats.recent,
                        count: 10,
                        dot: 22,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Older', style: context.text.bodySmall),
                        Text(
                          stats.lastAttended == null
                              ? 'Not seen yet'
                              : 'Last here ${fmtRelativeInline(stats.lastAttended!, store.today)}',
                          style: context.text.bodySmall,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SectionHeader('Last 6 months'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: HCard(
                child: RateBars(
                  height: 110,
                  showAllLabels: true,
                  data: [
                    for (final m in months)
                      BarDatum(
                        value: m.tally.rate,
                        label: DateFormat('MMM').format(m.month),
                        caption: m.tally.counted == 0
                            ? '${DateFormat('MMMM').format(m.month)} · no sessions'
                            : '${DateFormat('MMMM').format(m.month)} · '
                                  '${m.tally.attended} of ${m.tally.counted} · '
                                  '${formatRate(m.tally.rate)}',
                      ),
                  ],
                ),
              ),
            ),
          ],
          if (p.notes.isNotEmpty) ...[
            const SectionHeader('Notes'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: HCard(
                onTap: () => PlayerForm.open(context, player: p),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.sticky_note_2_outlined,
                      color: context.colors.onSurfaceVariant,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        p.notes,
                        style: context.text.bodyMedium?.copyWith(height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          SectionHeader(
            history.isEmpty
                ? 'History'
                : 'History · ${plural(history.length, 'session')}',
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: history.isEmpty
                ? HCard(
                    child: Text(
                      'No sessions yet. ${p.firstName}\'s attendance will '
                      'appear here after their first roll call.',
                      style: context.text.bodyMedium,
                    ),
                  )
                : Card(
                    child: Column(
                      children: [
                        for (final e in shownHistory)
                          ListTile(
                            onTap: () => _changeStatus(p, e),
                            title: Text(
                              fmtShortWithYear(e.session.date, store.today),
                            ),
                            subtitle: Text(
                              store.squad(e.session.squadId)?.name ?? '',
                            ),
                            trailing: StatusPill(
                              status: e.record.status,
                              dense: true,
                            ),
                          ),
                        if (history.length > shownHistory.length)
                          TextButton(
                            onPressed: () => setState(() => _showAll = true),
                            child: Text(
                              'Show all ${history.length}',
                            ),
                          ),
                      ],
                    ),
                  ),
          ),
          if (history.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
              child: Text(
                'Tap a session to correct it. Excused absences don\'t count '
                'against the attendance rate.',
                style: context.text.bodySmall,
              ),
            ),
        ],
      ),
    );
  }
}

class _BigStat extends StatelessWidget {
  const _BigStat({
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final Color iconColor;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 22, color: iconColor),
        const SizedBox(width: 8),
        Text(
          value,
          style: context.text.headlineSmall?.copyWith(fontSize: 24),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.text.bodySmall,
          ),
        ),
      ],
    );
  }
}

class _MiniCount extends StatelessWidget {
  const _MiniCount({required this.status, required this.count});

  final AttendanceStatus status;
  final int count;

  @override
  Widget build(BuildContext context) {
    final color = context.statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: context.isDark ? 0.14 : 0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Text(
            '$count',
            style: context.text.titleLarge?.copyWith(
              fontFamily: Brand.display,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          Text(
            status.label,
            style: context.text.labelMedium?.copyWith(
              fontSize: 12,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
