import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/models.dart';
import '../format.dart';
import '../scope.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/scoreboard.dart';
import 'history_screen.dart' show SquadFilter;
import 'player_screen.dart';
import 'squads_screen.dart';

class RosterScreen extends StatefulWidget {
  const RosterScreen({super.key});

  @override
  State<RosterScreen> createState() => _RosterScreenState();
}

class _RosterScreenState extends State<RosterScreen> {
  String? _squadId;
  String _query = '';
  bool _showArchived = false;
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _matches(Player p) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return p.name.toLowerCase().contains(q) || p.jersey?.toLowerCase() == q;
  }

  @override
  Widget build(BuildContext context) {
    final store = context.store;
    final squads = store.allSquads;
    if (_squadId != null && store.squad(_squadId!) == null) _squadId = null;
    final all = store.players;
    final players = all
        .where((p) => _squadId == null || p.squadIds.contains(_squadId))
        .where(_matches)
        .toList();
    final archived = store.archivedPlayers
        .where((p) => _squadId == null || p.squadIds.contains(_squadId))
        .where(_matches)
        .toList();

    return Scaffold(
      floatingActionButton: all.isEmpty && archived.isEmpty
          ? null
          : FloatingActionButton.extended(
              heroTag: 'add-player',
              onPressed: () => PlayerForm.open(context, squadId: _squadId),
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('Add player'),
            ),
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          slivers: [
            SliverToBoxAdapter(
              child: PageTitle(
                'Roster',
                subtitle: all.isEmpty ? null : plural(all.length, 'player'),
                actions: [
                  IconButton(
                    tooltip: 'Squads',
                    icon: const Icon(Icons.shield_outlined),
                    onPressed: () => SquadsScreen.open(context),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'More',
                    onSelected: (v) {
                      if (v == 'bulk') {
                        BulkAddSheet.open(context, squadId: _squadId);
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: 'bulk',
                        child: Text('Add several at once'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (all.length > 8)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                sliver: SliverToBoxAdapter(
                  child: TextField(
                    controller: _search,
                    onChanged: (v) => setState(() => _query = v),
                    onTapOutside: (_) => FocusScope.of(context).unfocus(),
                    decoration: InputDecoration(
                      hintText: 'Search players',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _query.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () => setState(() {
                                _search.clear();
                                _query = '';
                              }),
                            ),
                    ),
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
            if (all.isEmpty && archived.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                  icon: const Basketball(size: 64, rotation: -0.3),
                  title: 'Build your roster',
                  message:
                      'Add the kids you coach. Got a list from the academy? '
                      'Paste it in one go.',
                  action: Column(
                    children: [
                      FilledButton.icon(
                        onPressed: () => PlayerForm.open(context),
                        icon: const Icon(Icons.person_add_alt_1),
                        label: const Text('Add a player'),
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: () => BulkAddSheet.open(context),
                        icon: const Icon(Icons.format_list_bulleted),
                        label: const Text('Paste a list of names'),
                      ),
                    ],
                  ),
                ),
              )
            else if (players.isEmpty && archived.isEmpty)
              SliverToBoxAdapter(
                child: EmptyState(
                  title: _query.isEmpty ? 'No players here yet' : 'No matches',
                  message: _query.isEmpty
                      ? 'Add players to this squad, or move existing players '
                            'into it from their profile.'
                      : 'Nobody on the roster matches "$_query".',
                ),
              )
            else ...[
              const SliverToBoxAdapter(child: SizedBox(height: 8)),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverToBoxAdapter(
                  child: Card(
                    child: Column(
                      children: [
                        for (var i = 0; i < players.length; i++) ...[
                          if (i > 0)
                            const Divider(indent: 72, endIndent: 16),
                          RosterRow(
                            player: players[i],
                            showSquads: _squadId == null && squads.length > 1,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              if (archived.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: InkWell(
                    onTap: () => setState(() => _showArchived = !_showArchived),
                    child: SectionHeader(
                      'Archived · ${archived.length}',
                      trailing: Icon(
                        _showArchived ? Icons.expand_less : Icons.expand_more,
                        color: context.colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
                if (_showArchived)
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    sliver: SliverToBoxAdapter(
                      child: Card(
                        child: Column(
                          children: [
                            for (final p in archived)
                              RosterRow(player: p, showSquads: true),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ],
            const SliverToBoxAdapter(child: SizedBox(height: 96)),
          ],
        ),
      ),
    );
  }
}

class RosterRow extends StatelessWidget {
  const RosterRow({super.key, required this.player, this.showSquads = false});

  final Player player;
  final bool showSquads;

  @override
  Widget build(BuildContext context) {
    final store = context.store;
    final stats = store.statsOf(player.id);
    final squads = player.squadIds
        .map(store.squad)
        .whereType<Squad>()
        .toList();
    final String subtitle;
    if (player.archived) {
      subtitle = 'Archived';
    } else if (stats.tally.total == 0) {
      subtitle = 'New · no sessions yet';
    } else if (stats.lastAttended != null) {
      subtitle =
          'Last here ${fmtRelativeInline(stats.lastAttended!, store.today)}';
    } else {
      subtitle = 'Not seen yet';
    }

    return InkWell(
      onTap: () => PlayerScreen.open(context, player.id),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(
          children: [
            PlayerAvatar(
              player: player,
              size: 44,
              heroTag: 'avatar-${player.id}',
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          player.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.text.titleMedium,
                        ),
                      ),
                      if (stats.currentStreak >= 5) ...[
                        const SizedBox(width: 6),
                        const Icon(
                          Icons.local_fire_department,
                          size: 16,
                          color: Brand.orange,
                        ),
                        Text(
                          '${stats.currentStreak}',
                          style: const TextStyle(
                            fontFamily: Brand.display,
                            fontWeight: FontWeight.w800,
                            color: Brand.orange,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  if (showSquads && squads.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2, bottom: 2),
                      child: Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: [for (final s in squads) SquadTag(squad: s)],
                      ),
                    )
                  else
                    Text(subtitle, style: context.text.bodySmall),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  formatRate(stats.rate),
                  style: context.text.titleMedium?.copyWith(
                    fontFamily: Brand.display,
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                    color: rateColor(stats.rate, context.isDark),
                  ),
                ),
                const SizedBox(height: 4),
                FormGuide(newestFirst: stats.recent, dot: 7),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Add or edit a player.
class PlayerForm extends StatefulWidget {
  const PlayerForm({super.key, this.player, this.squadId});

  final Player? player;
  final String? squadId;

  static Future<void> open(
    BuildContext context, {
    Player? player,
    String? squadId,
  }) => showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => PlayerForm(player: player, squadId: squadId),
  );

  @override
  State<PlayerForm> createState() => _PlayerFormState();
}

class _PlayerFormState extends State<PlayerForm> {
  late final _name = TextEditingController(text: widget.player?.name);
  late final _jersey = TextEditingController(text: widget.player?.jersey);
  late final _notes = TextEditingController(text: widget.player?.notes);
  final _nameFocus = FocusNode();
  late Set<String> _squads;
  int _addedCount = 0;

  bool get _editing => widget.player != null;

  @override
  void initState() {
    super.initState();
    final store = context.readStore;
    final active = store.squads;
    _squads = widget.player?.squadIds.toSet() ??
        {
          if (widget.squadId != null)
            widget.squadId!
          else if (active.length == 1)
            active.first.id,
        };
  }

  @override
  void dispose() {
    _name.dispose();
    _jersey.dispose();
    _notes.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  void _save({required bool another}) {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    final store = context.readStore;
    if (_editing) {
      store.updatePlayer(
        widget.player!.copyWith(
          name: name,
          jersey: () => _jersey.text,
          squadIds: _squads,
          notes: _notes.text,
        ),
      );
      Navigator.pop(context);
      return;
    }
    store.addPlayer(
      name: name,
      jersey: _jersey.text,
      squadIds: _squads,
      notes: _notes.text,
    );
    HapticFeedback.lightImpact();
    if (another) {
      setState(() => _addedCount++);
      _name.clear();
      _jersey.clear();
      _notes.clear();
      _nameFocus.requestFocus();
    } else {
      Navigator.pop(context);
      showSnack(context, '$name added to the roster');
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.store;
    final squads = store.squads;
    final canSave = _name.text.trim().isNotEmpty;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _editing ? 'Edit player' : 'New player',
                      style: context.text.headlineSmall,
                    ),
                  ),
                  if (_addedCount > 0)
                    Text(
                      '$_addedCount added',
                      style: context.text.labelMedium?.copyWith(
                        color: context.statusColor(AttendanceStatus.present),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _name,
                      focusNode: _nameFocus,
                      autofocus: !_editing,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Name',
                        hintText: 'First and last name',
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 96,
                    child: TextField(
                      controller: _jersey,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.done,
                      maxLength: 3,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp('[0-9]')),
                      ],
                      onSubmitted: (_) => _save(another: !_editing),
                      decoration: const InputDecoration(
                        labelText: 'Jersey',
                        hintText: '#',
                        counterText: '',
                      ),
                    ),
                  ),
                ],
              ),
              if (squads.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text('SQUADS', style: context.text.labelSmall),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final s in squads)
                      FilterChip(
                        avatar: SquadDot(color: context.squadColor(s)),
                        label: Text(s.name),
                        selected: _squads.contains(s.id),
                        onSelected: (on) => setState(() {
                          on ? _squads.add(s.id) : _squads.remove(s.id);
                        }),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              TextField(
                controller: _notes,
                minLines: 2,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Notes (optional)',
                  hintText: 'Allergies, pickup, parent\'s number…',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 18),
              if (_editing)
                FilledButton(
                  onPressed: canSave ? () => _save(another: false) : null,
                  child: const Text('Save'),
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: canSave ? () => _save(another: true) : null,
                        child: const FittedBox(child: Text('Save & add another')),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: canSave
                            ? () => _save(another: false)
                            : (_addedCount > 0
                                  ? () => Navigator.pop(context)
                                  : null),
                        child: Text(
                          canSave || _addedCount == 0 ? 'Save' : 'Done',
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Paste a whole list of names at once — the fastest way to set up a squad.
class BulkAddSheet extends StatefulWidget {
  const BulkAddSheet({super.key, this.squadId});

  final String? squadId;

  static Future<void> open(BuildContext context, {String? squadId}) =>
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (_) => BulkAddSheet(squadId: squadId),
      );

  @override
  State<BulkAddSheet> createState() => _BulkAddSheetState();
}

class _BulkAddSheetState extends State<BulkAddSheet> {
  final _text = TextEditingController();
  late Set<String> _squads;

  @override
  void initState() {
    super.initState();
    final active = context.readStore.squads;
    _squads = {
      if (widget.squadId != null)
        widget.squadId!
      else if (active.isNotEmpty)
        active.first.id,
    };
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  List<String> get _names => parseNames(_text.text);

  @override
  Widget build(BuildContext context) {
    final store = context.store;
    final names = _names;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Add several players', style: context.text.headlineSmall),
              const SizedBox(height: 4),
              Text(
                'Type or paste one name per line.',
                style: context.text.bodySmall,
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _text,
                autofocus: true,
                minLines: 6,
                maxLines: 10,
                textCapitalization: TextCapitalization.words,
                keyboardType: TextInputType.multiline,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  hintText: 'Maya Rodriguez\nLeo Kim\nAarav Mehta',
                ),
              ),
              if (store.squads.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text('ADD TO', style: context.text.labelSmall),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final s in store.squads)
                      FilterChip(
                        avatar: SquadDot(color: context.squadColor(s)),
                        label: Text(s.name),
                        selected: _squads.contains(s.id),
                        onSelected: (on) => setState(() {
                          on ? _squads.add(s.id) : _squads.remove(s.id);
                        }),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 18),
              FilledButton(
                onPressed: names.isEmpty
                    ? null
                    : () {
                        store.addPlayers(names, _squads);
                        HapticFeedback.mediumImpact();
                        Navigator.pop(context);
                        showSnack(
                          context,
                          '${plural(names.length, 'player')} added',
                        );
                      },
                child: Text(
                  names.isEmpty
                      ? 'Add players'
                      : 'Add ${plural(names.length, 'player')}',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Splits pasted text into clean names. Handles numbered lists ("1. Maya"),
/// bullets, commas and stray whitespace, and drops duplicates.
List<String> parseNames(String text) {
  final lines = text.contains('\n') ? text.split('\n') : text.split(',');
  final seen = <String>{};
  final result = <String>[];
  for (final raw in lines) {
    final name = raw
        .replaceFirst(RegExp(r'^\s*(\d+[.)]|[-*•])\s*'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (name.isEmpty) continue;
    if (seen.add(name.toLowerCase())) result.add(name);
  }
  return result;
}
