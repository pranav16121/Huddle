import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/models.dart';
import '../../data/stats.dart';
import '../../data/store.dart';
import '../format.dart';
import '../scope.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/scoreboard.dart';
import 'session_screen.dart';

/// Live roll call. Designed for one-handed use courtside:
///
/// * tap a player when they arrive (tap again to undo)
/// * hold for Late / Excused / Away
/// * "Rest are here" for the common case where almost everyone came
///
/// Nothing is written until the first player is marked, and from then on
/// every tap is saved immediately — there is no "save" button to forget.
class RollCallScreen extends StatefulWidget {
  const RollCallScreen({super.key, this.sessionId, this.squadId, this.date})
    : assert(sessionId != null || squadId != null);

  final String? sessionId;
  final String? squadId;
  final DateTime? date;

  /// Opens the roll call for [squadId] on [date] (default: today), resuming
  /// the existing session for that day if there is one.
  static Future<void> open(
    BuildContext context, {
    required String squadId,
    DateTime? date,
  }) {
    final store = context.readStore;
    final day = dateOnly(date ?? store.today);
    final existing = store.sessionsOn(day, squadId: squadId);
    HapticFeedback.mediumImpact();
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => existing.isNotEmpty
            ? RollCallScreen(sessionId: existing.first.id)
            : RollCallScreen(squadId: squadId, date: day),
      ),
    );
  }

  static Future<void> edit(BuildContext context, String sessionId) =>
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => RollCallScreen(sessionId: sessionId)),
      );

  @override
  State<RollCallScreen> createState() => _RollCallScreenState();
}

enum _Sort { firstName, jersey }

class _RollCallScreenState extends State<RollCallScreen> {
  String? _sessionId;
  late String _squadId;
  late DateTime _date;

  /// Statuses before the session exists (nothing marked yet).
  final Map<String, AttendanceStatus> _draft = {};

  final _searchController = TextEditingController();
  String _query = '';
  bool _searching = false;
  _Sort _sort = _Sort.firstName;

  /// Per-player animation delays for the "rest are here" wave.
  Map<String, Duration> _wave = const {};
  Timer? _waveReset;
  bool _leaving = false;

  HuddleStore get _store => context.readStore;

  @override
  void initState() {
    super.initState();
    final store = context.readStore;
    final existing = widget.sessionId == null
        ? null
        : store.session(widget.sessionId!);
    if (existing != null) {
      _sessionId = existing.id;
      _squadId = existing.squadId;
      _date = existing.date;
    } else {
      _squadId = widget.squadId ?? '';
      _date = dateOnly(widget.date ?? store.today);
      for (final p in store.membersOf(_squadId)) {
        _draft[p.id] = AttendanceStatus.absent;
      }
    }
    _searching = _statuses(store).length > 20;
  }

  @override
  void dispose() {
    _searchController.dispose();
    _waveReset?.cancel();
    super.dispose();
  }

  Map<String, AttendanceStatus> _statuses(HuddleStore store) {
    final id = _sessionId;
    if (id == null) return _draft;
    return {for (final e in store.recordsOf(id).entries) e.key: e.value.status};
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  void _apply(Map<String, AttendanceStatus> changes) {
    if (changes.isEmpty) return;
    final store = _store;
    if (_sessionId == null) {
      setState(() => _draft.addAll(changes));
      if (_draft.values.any((s) => s != AttendanceStatus.absent)) {
        final session = store.createSession(
          squadId: _squadId,
          date: _date,
          statuses: Map.of(_draft),
        );
        setState(() => _sessionId = session.id);
      }
    } else {
      store.setStatuses(_sessionId!, changes);
    }
  }

  void _toggle(Player p, AttendanceStatus current) {
    if (current == AttendanceStatus.absent) {
      HapticFeedback.lightImpact();
      _apply({p.id: AttendanceStatus.present});
    } else {
      HapticFeedback.selectionClick();
      _apply({p.id: AttendanceStatus.absent});
    }
    _clearWave();
  }

  void _clearWave() {
    if (_wave.isNotEmpty) setState(() => _wave = const {});
  }

  void _restAreHere(List<Player> ordered, Map<String, AttendanceStatus> now) {
    final away = [
      for (final p in ordered)
        if (now[p.id] == AttendanceStatus.absent) p.id,
    ];
    if (away.isEmpty) return;
    HapticFeedback.mediumImpact();
    final previous = {for (final id in away) id: AttendanceStatus.absent};
    setState(() {
      _wave = {
        for (var i = 0; i < away.length; i++)
          away[i]: Duration(milliseconds: 28 * i),
      };
    });
    _waveReset?.cancel();
    _waveReset = Timer(Duration(milliseconds: 28 * away.length + 400), () {
      if (mounted) setState(() => _wave = const {});
    });
    _apply({for (final id in away) id: AttendanceStatus.present});
    showSnack(
      context,
      '${plural(away.length, 'more player')} marked here',
      actionLabel: 'Undo',
      onAction: () {
        if (!mounted) return;
        _clearWave();
        _apply(previous);
      },
    );
  }

  Future<void> _pickDate() async {
    final store = _store;
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(store.today.year - 3),
      lastDate: store.today,
      helpText: 'Session date',
    );
    if (picked == null || !mounted) return;
    final day = dateOnly(picked);
    setState(() => _date = day);
    final id = _sessionId;
    if (id != null) {
      final s = store.session(id);
      if (s != null) store.updateSession(s.copyWith(date: day));
    }
  }

  bool _isEmptySession(HuddleStore store) {
    final id = _sessionId;
    if (id == null || store.session(id) == null) return false;
    final t = store.tallyOf(id);
    return t.attended == 0 && t.excused == 0;
  }

  /// Returns true if the screen may close.
  Future<bool> _confirmLeave() async {
    final store = _store;
    if (!_isEmptySession(store)) return true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nobody marked here'),
        content: Text(
          'Discard this roll call, or keep it as a session nobody came to?',
          style: context.text.bodyLarge,
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(64, 46)),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (discard == null) return false; // dismissed: stay
    if (discard) {
      store.deleteSession(_sessionId!);
      _sessionId = null;
    }
    return true;
  }

  Future<void> _leave() async {
    if (_leaving) return;
    _leaving = true;
    final ok = await _confirmLeave();
    _leaving = false;
    if (ok && mounted) Navigator.of(context).pop();
  }

  Future<void> _done() async {
    if (_sessionId == null) {
      Navigator.of(context).pop();
      return;
    }
    if (_isEmptySession(_store)) {
      await _leave();
      return;
    }
    HapticFeedback.mediumImpact();
    final id = _sessionId!;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => SessionScreen(sessionId: id, justFinished: true),
      ),
    );
  }

  Future<void> _showStatusSheet(Player p, AttendanceStatus current) async {
    HapticFeedback.mediumImpact();
    final result = await showModalBottomSheet<Object>(
      context: context,
      // Lets the sheet grow past half the screen with large text.
      isScrollControlled: true,
      builder: (context) => StatusSheet(
        player: p,
        current: current,
        canRemove: _sessionId != null,
      ),
    );
    if (!mounted) return;
    if (result is AttendanceStatus) {
      _apply({p.id: result});
      _clearWave();
    } else if (result == StatusSheet.remove && _sessionId != null) {
      _store.removeFromSession(_sessionId!, p.id);
    }
  }

  Future<void> _addPlayer(Set<String> inSession) async {
    final result = await showModalBottomSheet<_AddResult>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _AddPlayerSheet(squadId: _squadId, excludeIds: inSession),
    );
    if (result == null || !mounted) return;
    final store = _store;
    final Player player;
    if (result.existing != null) {
      player = result.existing!;
    } else {
      player = store.addPlayer(name: result.name!, squadIds: {_squadId});
    }
    HapticFeedback.lightImpact();
    _apply({player.id: AttendanceStatus.present});
    showSnack(context, '${player.firstName} added and marked here');
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final store = context.store;
    if (_sessionId != null && store.session(_sessionId!) == null) {
      // The session was deleted elsewhere (e.g. from History). Close.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).maybePop();
      });
      return const Scaffold();
    }

    final squad = store.squad(_squadId);
    final statuses = _statuses(store);
    final tally = Tally.of(statuses.values);
    final everyone = statuses.keys
        .map(store.player)
        .whereType<Player>()
        .toList();
    everyone.sort(_compare);
    final q = _query.trim().toLowerCase();
    final shown = q.isEmpty
        ? everyone
        : everyone
              .where(
                (p) =>
                    p.name.toLowerCase().contains(q) ||
                    (p.jersey?.toLowerCase() == q),
              )
              .toList();
    final anyAway = tally.absent > 0;

    return PopScope(
      canPop: !_isEmptySession(store),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 0,
          toolbarHeight: 64,
          title: _Title(
            squad: squad,
            date: _date,
            today: store.today,
            onPickDate: _pickDate,
          ),
          actions: [
            IconButton(
              tooltip: 'Find player',
              icon: Icon(_searching ? Icons.search_off : Icons.search),
              onPressed: () => setState(() {
                _searching = !_searching;
                if (!_searching) {
                  _searchController.clear();
                  _query = '';
                }
              }),
            ),
            PopupMenuButton<String>(
              tooltip: 'More',
              onSelected: (v) {
                switch (v) {
                  case 'sort':
                    setState(
                      () => _sort = _sort == _Sort.firstName
                          ? _Sort.jersey
                          : _Sort.firstName,
                    );
                  case 'add':
                    _addPlayer(statuses.keys.toSet());
                  case 'reset':
                    final marked = {
                      for (final e in statuses.entries)
                        if (e.value != AttendanceStatus.absent) e.key: e.value,
                    };
                    _apply({
                      for (final id in marked.keys) id: AttendanceStatus.absent,
                    });
                    showSnack(
                      context,
                      'Cleared ${plural(marked.length, 'mark')}',
                      actionLabel: 'Undo',
                      onAction: () {
                        if (mounted) _apply(marked);
                      },
                    );
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'sort',
                  child: Text(
                    _sort == _Sort.firstName
                        ? 'Sort by jersey number'
                        : 'Sort by name',
                  ),
                ),
                const PopupMenuItem(value: 'add', child: Text('Add a player')),
                if (tally.absent != tally.total)
                  const PopupMenuItem(
                    value: 'reset',
                    child: Text('Clear all marks'),
                  ),
              ],
            ),
          ],
        ),
        body: CustomScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              sliver: SliverToBoxAdapter(
                child: Scoreboard(
                  here: tally.present,
                  late: tally.late,
                  away: tally.absent,
                  excused: tally.excused,
                  total: tally.total,
                ),
              ),
            ),
            if (!store.rollCallTipSeen && everyone.isNotEmpty)
              SliverToBoxAdapter(
                child: _Tip(onDismiss: store.markRollCallTipSeen),
              ),
            if (_searching)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                sliver: SliverToBoxAdapter(
                  child: TextField(
                    controller: _searchController,
                    onChanged: (v) => setState(() => _query = v),
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: 'Find by name or number',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _query.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () => setState(() {
                                _searchController.clear();
                                _query = '';
                              }),
                            ),
                    ),
                  ),
                ),
              ),
            if (everyone.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                  icon: const Basketball(size: 64),
                  title: 'No players in this squad yet',
                  message:
                      'Add the kids who are here today. They\'ll join '
                      '${squad?.name ?? 'the squad'} for next time too.',
                  action: FilledButton.icon(
                    onPressed: () => _addPlayer(const {}),
                    icon: const Icon(Icons.person_add_alt_1),
                    label: const Text('Add a player'),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                sliver: SliverGrid(
                  gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 150,
                    // Avatar and padding, plus the two name lines, which
                    // grow with the phone's font size.
                    mainAxisExtent:
                        104 + MediaQuery.textScalerOf(context).scale(34),
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                  ),
                  delegate: SliverChildBuilderDelegate((context, i) {
                    if (i == shown.length) {
                      return _AddTile(
                        onTap: () => _addPlayer(statuses.keys.toSet()),
                      );
                    }
                    final p = shown[i];
                    final s = statuses[p.id] ?? AttendanceStatus.absent;
                    return _PlayerTile(
                      key: ValueKey(p.id),
                      player: p,
                      status: s,
                      delay: _wave[p.id] ?? Duration.zero,
                      onTap: () => _toggle(p, s),
                      onLongPress: () => _showStatusSheet(p, s),
                    );
                  }, childCount: shown.length + (q.isEmpty ? 1 : 0)),
                ),
              ),
          ],
        ),
        bottomNavigationBar: _BottomBar(
          canFillRest: anyAway && everyone.isNotEmpty,
          arrived: tally.attended,
          total: tally.total,
          onRestHere: () => _restAreHere(everyone, statuses),
          onDone: _done,
        ),
      ),
    );
  }

  int _compare(Player a, Player b) {
    if (_sort == _Sort.jersey) {
      final ja = int.tryParse(a.jersey ?? '');
      final jb = int.tryParse(b.jersey ?? '');
      if (ja != null && jb != null && ja != jb) return ja.compareTo(jb);
      if (ja != null && jb == null) return -1;
      if (ja == null && jb != null) return 1;
    }
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  }
}

class _Title extends StatelessWidget {
  const _Title({
    required this.squad,
    required this.date,
    required this.today,
    required this.onPickDate,
  });

  final Squad? squad;
  final DateTime date;
  final DateTime today;
  final VoidCallback onPickDate;

  @override
  Widget build(BuildContext context) {
    final rel = fmtRelative(date, today);
    final label = rel == 'Today' || rel == 'Yesterday'
        ? '$rel · ${fmtShort(date)}'
        : fmtShortWithYear(date, today);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            SquadDot(color: context.squadColor(squad), size: 11),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                squad?.name ?? 'Roll call',
                overflow: TextOverflow.ellipsis,
                style: context.text.headlineSmall?.copyWith(fontSize: 23),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        InkWell(
          onTap: onPickDate,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.labelMedium,
                  ),
                ),
                Icon(
                  Icons.arrow_drop_down,
                  size: 20,
                  color: context.colors.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Tip extends StatelessWidget {
  const _Tip({required this.onDismiss});

  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
        decoration: BoxDecoration(
          color: context.colors.primaryContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Icon(
              Icons.touch_app_outlined,
              color: context.colors.onPrimaryContainer,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Tap a player when they arrive.\n'
                'Hold for Late or Excused.',
                style: context.text.bodyMedium?.copyWith(
                  color: context.colors.onPrimaryContainer,
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                ),
              ),
            ),
            TextButton(onPressed: onDismiss, child: const Text('Got it')),
          ],
        ),
      ),
    );
  }
}

class _PlayerTile extends StatefulWidget {
  const _PlayerTile({
    super.key,
    required this.player,
    required this.status,
    required this.delay,
    required this.onTap,
    required this.onLongPress,
  });

  final Player player;
  final AttendanceStatus status;
  final Duration delay;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  State<_PlayerTile> createState() => _PlayerTileState();
}

class _PlayerTileState extends State<_PlayerTile> {
  late AttendanceStatus _shown = widget.status;
  Timer? _timer;

  @override
  void didUpdateWidget(_PlayerTile old) {
    super.didUpdateWidget(old);
    if (widget.status == _shown) return;
    _timer?.cancel();
    if (widget.delay > Duration.zero) {
      _timer = Timer(widget.delay, () {
        if (mounted) setState(() => _shown = widget.status);
      });
    } else {
      _shown = widget.status;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.player;
    final marked = _shown != AttendanceStatus.absent;
    final color = marked ? context.statusColor(_shown) : null;
    final parts = p.name.trim().split(RegExp(r'\s+'));
    final rest = parts.length > 1 ? parts.sublist(1).join(' ') : '';
    final onColor = Colors.white;

    return Semantics(
      button: true,
      label: '${p.name}, ${_shown.label}',
      hint: 'Tap to toggle here. Long press for late or excused.',
      excludeSemantics: true,
      child: Pressable(
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: color ?? context.colors.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: color ?? context.colors.outlineVariant,
              width: 1.5,
            ),
            boxShadow: color == null
                ? null
                : [
                    BoxShadow(
                      color: color.withValues(alpha: 0.32),
                      blurRadius: 14,
                      offset: const Offset(0, 5),
                    ),
                  ],
          ),
          padding: const EdgeInsets.fromLTRB(6, 12, 6, 10),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 240),
                    padding: const EdgeInsets.all(2.5),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: marked
                          ? Colors.white.withValues(alpha: 0.9)
                          : Colors.transparent,
                    ),
                    child: PlayerAvatar(player: p, size: 54),
                  ),
                  Positioned(
                    right: -6,
                    top: -6,
                    child: AnimatedScale(
                      scale: marked ? 1 : 0,
                      duration: const Duration(milliseconds: 320),
                      curve: marked ? Curves.elasticOut : Curves.easeIn,
                      child: Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.15),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                        child: Icon(
                          statusIcon(_shown),
                          size: 18,
                          color: color ?? Colors.transparent,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                parts.first,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: Brand.body,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  height: 1.1,
                  color: marked ? onColor : context.colors.onSurface,
                ),
              ),
              Text(
                _shown == AttendanceStatus.late ||
                        _shown == AttendanceStatus.excused
                    ? _shown.label.toUpperCase()
                    : rest,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: Brand.body,
                  fontWeight: FontWeight.w600,
                  fontSize: 12.5,
                  letterSpacing: marked && _shown != AttendanceStatus.present
                      ? 1
                      : 0,
                  color: marked
                      ? onColor.withValues(alpha: 0.85)
                      : context.colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddTile extends StatelessWidget {
  const _AddTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: CustomPaint(
        painter: _DashedBorder(context.colors.outline),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.person_add_alt_1_outlined,
                size: 30,
                color: context.colors.onSurfaceVariant,
              ),
              const SizedBox(height: 8),
              Text(
                'Add player',
                style: context.text.labelMedium?.copyWith(fontSize: 14),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashedBorder extends CustomPainter {
  _DashedBorder(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      (Offset.zero & size).deflate(1),
      const Radius.circular(20),
    );
    final paint = Paint()
      ..color = color.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final path = Path()..addRRect(rrect);
    for (final metric in path.computeMetrics()) {
      for (double d = 0; d < metric.length; d += 10) {
        canvas.drawPath(metric.extractPath(d, d + 5), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorder old) => old.color != color;
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.canFillRest,
    required this.arrived,
    required this.total,
    required this.onRestHere,
    required this.onDone,
  });

  final bool canFillRest;
  final int arrived;
  final int total;
  final VoidCallback onRestHere;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerLowest,
        border: Border(top: BorderSide(color: context.colors.outlineVariant)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: canFillRest ? onRestHere : null,
                  icon: const Icon(Icons.done_all_rounded),
                  label: const FittedBox(child: Text('Rest are here')),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: onDone,
                  child: FittedBox(
                    child: Text(total == 0 ? 'Done' : 'Done · $arrived/$total'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet with big status buttons. Pops with an [AttendanceStatus], or
/// [StatusSheet.remove].
class StatusSheet extends StatelessWidget {
  const StatusSheet({
    super.key,
    required this.player,
    required this.current,
    this.canRemove = false,
    this.subtitle,
  });

  final Player player;
  final AttendanceStatus current;
  final bool canRemove;
  final String? subtitle;

  static const remove = 'remove';

  static const _hints = {
    AttendanceStatus.present: 'On time',
    AttendanceStatus.late: 'Arrived after the start',
    AttendanceStatus.excused: 'Told you in advance',
    AttendanceStatus.absent: 'Didn\'t come',
  };

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                PlayerAvatar(player: player, size: 48),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(player.name, style: context.text.titleLarge),
                      if (subtitle != null)
                        Text(subtitle!, style: context.text.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            // Two rows of two. Each row is as tall as its tallest option, so
            // large text grows the buttons instead of spilling out of them.
            for (final row in const [
              [AttendanceStatus.present, AttendanceStatus.late],
              [AttendanceStatus.excused, AttendanceStatus.absent],
            ]) ...[
              if (row.first != AttendanceStatus.present)
                const SizedBox(height: 10),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final s in row) ...[
                      if (s != row.first) const SizedBox(width: 10),
                      Expanded(
                        child: _StatusOption(
                          status: s,
                          hint: _hints[s]!,
                          selected: s == current,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
            if (canRemove) ...[
              const SizedBox(height: 6),
              TextButton(
                onPressed: () => Navigator.pop(context, remove),
                child: Text(
                  'Remove from this session',
                  style: TextStyle(color: context.colors.onSurfaceVariant),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusOption extends StatelessWidget {
  const _StatusOption({
    required this.status,
    required this.hint,
    required this.selected,
  });

  final AttendanceStatus status;
  final String hint;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final color = context.statusColor(status);
    return Pressable(
      onTap: () {
        HapticFeedback.lightImpact();
        Navigator.pop(context, status);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        constraints: const BoxConstraints(minHeight: 84),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? color
              : color.withValues(alpha: context.isDark ? 0.16 : 0.1),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withValues(alpha: 0.5), width: 1.5),
        ),
        child: Row(
          children: [
            Icon(
              statusIcon(status),
              color: selected ? Colors.white : color,
              size: 28,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    status.label,
                    style: context.text.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: selected ? Colors.white : null,
                    ),
                  ),
                  Text(
                    hint,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.bodySmall?.copyWith(
                      fontSize: 12,
                      color: selected
                          ? Colors.white.withValues(alpha: 0.85)
                          : null,
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

class _AddResult {
  _AddResult.newPlayer(String this.name) : existing = null;
  _AddResult.existing(Player this.existing) : name = null;

  final String? name;
  final Player? existing;
}

/// Add a walk-in: a brand-new kid (joins the squad), or someone from another
/// squad who's training with this group today.
class _AddPlayerSheet extends StatefulWidget {
  const _AddPlayerSheet({required this.squadId, required this.excludeIds});

  final String squadId;
  final Set<String> excludeIds;

  @override
  State<_AddPlayerSheet> createState() => _AddPlayerSheetState();
}

class _AddPlayerSheetState extends State<_AddPlayerSheet> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.store;
    final squad = store.squad(widget.squadId);
    final name = _controller.text.trim();
    final q = name.toLowerCase();
    final others = store.players
        .where((p) => !widget.excludeIds.contains(p.id))
        .where((p) => q.isEmpty || p.name.toLowerCase().contains(q))
        .take(6)
        .toList();

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Who just walked in?', style: context.text.headlineSmall),
              const SizedBox(height: 14),
              TextField(
                controller: _controller,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.done,
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) {
                  if (name.isNotEmpty) {
                    Navigator.pop(context, _AddResult.newPlayer(name));
                  }
                },
                decoration: const InputDecoration(
                  hintText: 'Player name',
                  prefixIcon: Icon(Icons.person_outline),
                ),
              ),
              if (others.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text('ALREADY IN HUDDLE', style: context.text.labelSmall),
                const SizedBox(height: 4),
                for (final p in others)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: PlayerAvatar(player: p, size: 40),
                    title: Text(p.name),
                    subtitle: Text(
                      p.squadIds
                          .map((id) => store.squad(id)?.name)
                          .whereType<String>()
                          .join(', ')
                          .ifEmpty('No squad'),
                    ),
                    trailing: const Icon(Icons.add_circle_outline),
                    onTap: () => Navigator.pop(context, _AddResult.existing(p)),
                  ),
              ],
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: name.isEmpty
                    ? null
                    : () => Navigator.pop(context, _AddResult.newPlayer(name)),
                icon: const Icon(Icons.check),
                label: Text(
                  name.isEmpty
                      ? 'Type a name'
                      : 'Add $name to ${squad?.name ?? 'squad'}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
