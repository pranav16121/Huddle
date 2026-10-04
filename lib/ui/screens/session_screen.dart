import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/models.dart';
import '../../data/store.dart';
import '../format.dart';
import '../scope.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/confetti.dart';
import 'player_screen.dart';
import 'roll_call_screen.dart';

/// Summary of one session. Shown right after a roll call ("final buzzer")
/// and when opening a session from History.
class SessionScreen extends StatefulWidget {
  const SessionScreen({
    super.key,
    required this.sessionId,
    this.justFinished = false,
  });

  final String sessionId;
  final bool justFinished;

  static Future<void> open(BuildContext context, String sessionId) =>
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => SessionScreen(sessionId: sessionId)),
      );

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen> {
  late final TextEditingController _note;
  Timer? _noteDebounce;
  bool _celebrate = false;
  late final HuddleStore _store = context.readStore;

  @override
  void initState() {
    super.initState();
    final session = _store.session(widget.sessionId);
    _note = TextEditingController(text: session?.note ?? '');
    if (widget.justFinished) {
      final t = _store.tallyOf(widget.sessionId);
      if (t.counted > 0 && t.absent == 0) {
        _celebrate = true;
        HapticFeedback.heavyImpact();
      }
    }
  }

  @override
  void dispose() {
    _noteDebounce?.cancel();
    // The widget tree is locked during dispose, so save just after.
    final store = _store;
    final id = widget.sessionId;
    final text = _note.text.trim();
    scheduleMicrotask(() => _writeNote(store, id, text));
    _note.dispose();
    super.dispose();
  }

  static void _writeNote(HuddleStore store, String id, String text) {
    final session = store.session(id);
    if (session != null && session.note != text) {
      store.updateSession(session.copyWith(note: text));
    }
  }

  void _saveNote() => _writeNote(_store, widget.sessionId, _note.text.trim());

  void _onNoteChanged(String _) {
    _noteDebounce?.cancel();
    _noteDebounce = Timer(const Duration(milliseconds: 700), _saveNote);
  }

  Future<void> _delete(Session session, Squad? squad) async {
    final ok = await confirm(
      context,
      title: 'Delete this session?',
      message:
          'The attendance for ${squad?.name ?? 'this squad'} on '
          '${fmtShort(session.date)} will be removed from history and stats.',
      action: 'Delete',
      destructive: true,
    );
    if (!ok || !mounted) return;
    _noteDebounce?.cancel();
    final messenger = ScaffoldMessenger.of(context);
    final deleted = _store.deleteSession(session.id);
    Navigator.of(context).pop();
    if (deleted == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: const Text('Session deleted'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => _store.restoreSession(deleted),
          ),
        ),
      );
  }

  Future<void> _changeStatus(Player p, AttendanceStatus current) async {
    final result = await showModalBottomSheet<Object>(
      context: context,
      // Lets the sheet grow past half the screen with large text.
      isScrollControlled: true,
      builder: (_) => StatusSheet(
        player: p,
        current: current,
        canRemove: true,
        subtitle: 'Change attendance for this session',
      ),
    );
    if (!mounted) return;
    if (result is AttendanceStatus) {
      _store.setStatus(widget.sessionId, p.id, result);
    } else if (result == StatusSheet.remove) {
      _store.removeFromSession(widget.sessionId, p.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.store;
    final session = store.session(widget.sessionId);
    if (session == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).maybePop();
      });
      return const Scaffold();
    }
    final squad = store.squad(session.squadId);
    final tally = store.tallyOf(session.id);
    final records = store.recordsOf(session.id);
    final groups = <AttendanceStatus, List<Player>>{
      for (final s in AttendanceStatus.values) s: [],
    };
    for (final r in records.values) {
      final p = store.player(r.playerId);
      if (p != null) groups[r.status]!.add(p);
    }
    for (final list in groups.values) {
      list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    }
    final fullHouse = tally.counted > 0 && tally.absent == 0;

    return Scaffold(
      appBar: AppBar(
        leading: widget.justFinished
            ? IconButton(
                tooltip: 'Close',
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              )
            : null,
        title: widget.justFinished ? null : Text(fmtShort(session.date)),
        actions: [
          IconButton(
            tooltip: 'Edit attendance',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => RollCallScreen.edit(context, session.id),
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'delete') _delete(session, squad);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'delete', child: Text('Delete session')),
            ],
          ),
        ],
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              _Header(
                session: session,
                squad: squad,
                arrived: tally.attended,
                total: tally.total,
                rate: tally.rate,
                fullHouse: fullHouse,
                today: store.today,
              ),
              const SizedBox(height: 18),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    for (final s in AttendanceStatus.values) ...[
                      Expanded(
                        child: _CountChip(status: s, count: tally.count(s)),
                      ),
                      if (s != AttendanceStatus.absent)
                        const SizedBox(width: 8),
                    ],
                  ],
                ),
              ),
              for (final s in [
                AttendanceStatus.absent,
                AttendanceStatus.late,
                AttendanceStatus.excused,
                AttendanceStatus.present,
              ])
                if (groups[s]!.isNotEmpty) ...[
                  SectionHeader(
                    '${s == AttendanceStatus.absent ? 'Away' : s.label} · '
                    '${groups[s]!.length}',
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Card(
                      child: Column(
                        children: [
                          for (final p in groups[s]!)
                            _PlayerRow(
                              player: p,
                              status: s,
                              note: s == AttendanceStatus.absent
                                  ? _nudge(store, p)
                                  : null,
                              onTap: () => _changeStatus(p, s),
                              onOpen: () => PlayerScreen.open(context, p.id),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              const SectionHeader('Session note'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _note,
                  onChanged: _onNoteChanged,
                  onTapOutside: (_) => FocusScope.of(context).unfocus(),
                  minLines: 2,
                  maxLines: 5,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    hintText: 'Drills, focus, injuries, anything to remember…',
                  ),
                ),
              ),
            ],
          ),
          if (_celebrate) const Positioned.fill(child: ConfettiBurst()),
        ],
      ),
      bottomNavigationBar: widget.justFinished
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Done'),
                ),
              ),
            )
          : null,
    );
  }

  String? _nudge(HuddleStore store, Player p) {
    final stats = store.statsOf(p.id);
    if (stats.missedInARow >= 2) {
      return 'Missed ${stats.missedInARow} in a row';
    }
    return null;
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.session,
    required this.squad,
    required this.arrived,
    required this.total,
    required this.rate,
    required this.fullHouse,
    required this.today,
  });

  final Session session;
  final Squad? squad;
  final int arrived;
  final int total;
  final double? rate;
  final bool fullHouse;
  final DateTime today;

  String get _headline {
    final r = rate;
    if (r == null) return 'No one expected';
    if (fullHouse) return 'Full house!';
    if (r >= 0.9) return 'Great turnout';
    if (r >= 0.75) return 'Solid session';
    if (r >= 0.5) return 'Okay turnout';
    return 'A quiet one';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (squad != null) SquadTag(squad: squad!),
        const SizedBox(height: 6),
        Text(
          fmtRelative(session.date, today) == 'Today'
              ? 'Today · ${fmtShort(session.date)}'
              : fmtLong(session.date),
          style: context.text.labelMedium?.copyWith(fontSize: 14),
        ),
        const SizedBox(height: 18),
        RateRing(
          rate: rate,
          size: 176,
          stroke: 16,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: '$arrived'),
                    TextSpan(
                      text: '/$total',
                      style: TextStyle(
                        color: context.colors.onSurfaceVariant,
                        fontSize: 30,
                      ),
                    ),
                  ],
                ),
                style: context.text.displayMedium?.copyWith(fontSize: 52),
              ),
              Text('HERE', style: context.text.labelSmall),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          _headline,
          style: context.text.headlineLarge?.copyWith(
            color: fullHouse ? Brand.orange : null,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          rate == null
              ? 'Everyone was excused'
              : '${formatRate(rate)} attendance'
                    '${fullHouse ? ' · every single player showed up' : ''}',
          style: context.text.bodyMedium?.copyWith(
            color: context.colors.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _CountChip extends StatelessWidget {
  const _CountChip({required this.status, required this.count});

  final AttendanceStatus status;
  final int count;

  @override
  Widget build(BuildContext context) {
    final color = context.statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: context.isDark ? 0.16 : 0.1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Text(
            '$count',
            style: context.text.headlineMedium?.copyWith(color: color),
          ),
          Text(
            status.label,
            style: context.text.labelMedium?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

class _PlayerRow extends StatelessWidget {
  const _PlayerRow({
    required this.player,
    required this.status,
    required this.onTap,
    required this.onOpen,
    this.note,
  });

  final Player player;
  final AttendanceStatus status;
  final String? note;
  final VoidCallback onTap;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      onLongPress: onOpen,
      leading: GestureDetector(
        onTap: onOpen,
        child: PlayerAvatar(player: player, size: 42),
      ),
      title: Text(player.name),
      subtitle: note == null
          ? null
          : Text(
              note!,
              style: context.text.bodySmall?.copyWith(
                color: context.statusColor(AttendanceStatus.absent),
                fontWeight: FontWeight.w600,
              ),
            ),
      trailing: StatusPill(status: status, dense: true),
    );
  }
}
