import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/models.dart';
import '../format.dart';
import '../scope.dart';
import '../theme.dart';
import '../widgets/common.dart';

class SquadsScreen extends StatelessWidget {
  const SquadsScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => const SquadsScreen()));

  @override
  Widget build(BuildContext context) {
    final store = context.store;
    final active = store.squads;
    final archived = store.allSquads.where((s) => s.archived).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Squads')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'add-squad',
        onPressed: () => SquadForm.open(context),
        icon: const Icon(Icons.add),
        label: const Text('New squad'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
        children: [
          if (active.isEmpty)
            const EmptyState(
              title: 'No squads',
              message:
                  'A squad is a group you coach together, like "U10 '
                  'Saturday". Players can be in more than one.',
            ),
          for (final s in active) ...[
            _SquadCard(squad: s),
            const SizedBox(height: 10),
          ],
          if (archived.isNotEmpty) ...[
            const SectionHeader(
              'Archived',
              padding: EdgeInsets.fromLTRB(4, 16, 4, 10),
            ),
            for (final s in archived) ...[
              _SquadCard(squad: s),
              const SizedBox(height: 10),
            ],
          ],
        ],
      ),
    );
  }
}

class _SquadCard extends StatelessWidget {
  const _SquadCard({required this.squad});

  final Squad squad;

  @override
  Widget build(BuildContext context) {
    final store = context.store;
    final members = store.membersOf(squad.id).length;
    final sessions = store.sessionsOf(squad.id).length;
    final start = squad.startMinutes;
    return HCard(
      onTap: () => SquadForm.open(context, squad: squad),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: context.squadColor(squad).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(Icons.shield, color: context.squadColor(squad)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(squad.name, style: context.text.titleMedium),
                const SizedBox(height: 2),
                Text(
                  [
                    fmtWeekdays(squad.weekdays),
                    if (start != null) fmtMinutes(context, start),
                  ].join(' · '),
                  style: context.text.bodySmall,
                ),
                Text(
                  '${plural(members, 'player')} · ${plural(sessions, 'session')}',
                  style: context.text.bodySmall,
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: context.colors.onSurfaceVariant),
        ],
      ),
    );
  }
}

/// Create or edit a squad.
class SquadForm extends StatefulWidget {
  const SquadForm({super.key, this.squad});

  final Squad? squad;

  static Future<void> open(BuildContext context, {Squad? squad}) =>
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (_) => SquadForm(squad: squad),
      );

  @override
  State<SquadForm> createState() => _SquadFormState();
}

class _SquadFormState extends State<SquadForm> {
  late final _name = TextEditingController(text: widget.squad?.name);
  late int _color =
      widget.squad?.colorIndex ??
      context.readStore.allSquads.length % Brand.squadColors.length;
  late final Set<int> _days = {...?widget.squad?.weekdays};
  late int? _start = widget.squad?.startMinutes;

  bool get _editing => widget.squad != null;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    final store = context.readStore;
    if (_editing) {
      store.updateSquad(
        widget.squad!.copyWith(
          name: name,
          colorIndex: _color,
          weekdays: _days,
          startMinutes: () => _start,
        ),
      );
    } else {
      store.addSquad(
        name: name,
        colorIndex: _color,
        weekdays: _days,
        startMinutes: _start,
      );
    }
    HapticFeedback.lightImpact();
    Navigator.pop(context);
  }

  Future<void> _pickTime() async {
    final initial = _start ?? 17 * 60;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: initial ~/ 60, minute: initial % 60),
      helpText: 'Usual start time',
    );
    if (picked != null) setState(() => _start = picked.hour * 60 + picked.minute);
  }

  Future<void> _archive() async {
    final squad = widget.squad!;
    final store = context.readStore;
    store.setSquadArchived(squad.id, !squad.archived);
    Navigator.pop(context);
    showSnack(
      context,
      squad.archived ? '${squad.name} restored' : '${squad.name} archived',
      actionLabel: 'Undo',
      onAction: () => store.setSquadArchived(squad.id, squad.archived),
    );
  }

  Future<void> _delete() async {
    final squad = widget.squad!;
    final store = context.readStore;
    final sessions = store.sessionsOf(squad.id).length;
    final ok = await confirm(
      context,
      title: 'Delete ${squad.name}?',
      message: sessions == 0
          ? 'Players stay on your roster.'
          : 'This permanently deletes ${plural(sessions, 'session')} of '
                'attendance history. Players stay on your roster.\n\n'
                'To keep the history, archive the squad instead.',
      action: 'Delete',
      destructive: true,
    );
    if (!ok || !mounted) return;
    store.deleteSquad(squad.id);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
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
              Text(
                _editing ? 'Edit squad' : 'New squad',
                style: context.text.headlineSmall,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _name,
                autofocus: !_editing,
                textCapitalization: TextCapitalization.words,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Squad name',
                  hintText: 'e.g. U10 Saturday',
                ),
              ),
              const SizedBox(height: 18),
              Text('COLOUR', style: context.text.labelSmall),
              const SizedBox(height: 10),
              ColorPicker(
                selected: _color,
                onChanged: (i) => setState(() => _color = i),
              ),
              const SizedBox(height: 18),
              Text('TRAINING DAYS', style: context.text.labelSmall),
              const SizedBox(height: 10),
              WeekdayPicker(
                selected: _days,
                onChanged: (d) => setState(() {
                  _days.contains(d) ? _days.remove(d) : _days.add(d);
                }),
              ),
              const SizedBox(height: 6),
              Text(
                'Huddle puts this squad front and centre on these days.',
                style: context.text.bodySmall,
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        alignment: Alignment.centerLeft,
                      ),
                      onPressed: _pickTime,
                      icon: const Icon(Icons.schedule),
                      label: Text(
                        _start == null
                            ? 'Add a start time (optional)'
                            : 'Starts at ${fmtMinutes(context, _start!)}',
                      ),
                    ),
                  ),
                  if (_start != null)
                    IconButton(
                      tooltip: 'Clear time',
                      onPressed: () => setState(() => _start = null),
                      icon: const Icon(Icons.close),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: canSave ? _save : null,
                child: Text(_editing ? 'Save' : 'Create squad'),
              ),
              if (_editing) ...[
                const SizedBox(height: 18),
                const Divider(),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: TextButton.icon(
                        onPressed: _archive,
                        icon: Icon(
                          widget.squad!.archived
                              ? Icons.unarchive_outlined
                              : Icons.archive_outlined,
                        ),
                        label: Text(
                          widget.squad!.archived ? 'Restore' : 'Archive',
                        ),
                      ),
                    ),
                    Expanded(
                      child: TextButton.icon(
                        style: TextButton.styleFrom(
                          foregroundColor: context.colors.error,
                        ),
                        onPressed: _delete,
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Delete'),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class ColorPicker extends StatelessWidget {
  const ColorPicker({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (var i = 0; i < Brand.squadColors.length; i++)
          Semantics(
            selected: i == selected,
            button: true,
            label: 'Colour ${i + 1}',
            child: Pressable(
              onTap: () {
                HapticFeedback.selectionClick();
                onChanged(i);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Brand.squadColors[i],
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: i == selected
                        ? context.colors.onSurface
                        : Colors.transparent,
                    width: 3,
                  ),
                ),
                child: i == selected
                    ? const Icon(Icons.check, color: Colors.white, size: 20)
                    : null,
              ),
            ),
          ),
      ],
    );
  }
}

class WeekdayPicker extends StatelessWidget {
  const WeekdayPicker({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final Set<int> selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var d = 1; d <= 7; d++) ...[
          if (d > 1) const SizedBox(width: 6),
          Expanded(
            child: Semantics(
              selected: selected.contains(d),
              button: true,
              label: weekdayShort[d - 1],
              excludeSemantics: true,
              child: Pressable(
                onTap: () {
                  HapticFeedback.selectionClick();
                  onChanged(d);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selected.contains(d)
                        ? Brand.orange
                        : context.colors.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    weekdayLetters[d - 1],
                    style: TextStyle(
                      fontFamily: Brand.display,
                      fontWeight: FontWeight.w800,
                      fontSize: 17,
                      color: selected.contains(d)
                          ? Colors.white
                          : context.colors.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
