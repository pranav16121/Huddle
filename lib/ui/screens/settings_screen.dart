import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/auto_backup.dart';
import '../../data/backup.dart';
import '../../data/models.dart';
import '../../data/store.dart';
import '../format.dart';
import '../scope.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/scoreboard.dart';
import 'squads_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final _name = TextEditingController(text: context.readStore.coachName);
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() task, {String? error}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await task();
    } catch (e) {
      if (mounted) showSnack(context, error ?? 'Something went wrong: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restoreFromFile() async {
    await _run(() async {
      final Snapshot? snapshot;
      try {
        snapshot = await pickBackup();
      } on FormatException catch (e) {
        if (mounted) showSnack(context, e.message);
        return;
      }
      if (snapshot == null || !mounted) return;
      final restored = await confirmRestore(context, snapshot);
      if (restored && mounted) _name.text = context.readStore.coachName;
    }, error: 'Couldn\'t read that file.');
  }

  @override
  Widget build(BuildContext context) {
    final store = context.store;
    final hasSessions = store.sessions.isNotEmpty;
    final backups = BackupScope.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: AbsorbPointer(
        absorbing: _busy,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 40),
          children: [
            const SectionHeader('You'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                onChanged: store.setCoachName,
                onTapOutside: (_) => FocusScope.of(context).unfocus(),
                decoration: const InputDecoration(
                  labelText: 'Your name',
                  hintText: 'Shown in the greeting on Today',
                  prefixIcon: Icon(Icons.sports_outlined),
                ),
              ),
            ),
            const SectionHeader('Appearance'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SegmentedButton<ThemeMode>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: ThemeMode.system,
                    label: Text('Auto'),
                    icon: Icon(Icons.brightness_auto_outlined),
                  ),
                  ButtonSegment(
                    value: ThemeMode.light,
                    label: Text('Light'),
                    icon: Icon(Icons.light_mode_outlined),
                  ),
                  ButtonSegment(
                    value: ThemeMode.dark,
                    label: Text('Dark'),
                    icon: Icon(Icons.dark_mode_outlined),
                  ),
                ],
                selected: {store.themeMode},
                onSelectionChanged: (s) => store.setThemeMode(s.first),
              ),
            ),
            const SectionHeader('Coaching'),
            _Group(
              children: [
                ListTile(
                  leading: const Icon(Icons.shield_outlined),
                  title: const Text('Squads'),
                  subtitle: Text(plural(store.squads.length, 'active squad')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => SquadsScreen.open(context),
                ),
              ],
            ),
            const SectionHeader('Your data'),
            _Group(
              children: [
                if (backups != null) ...[
                  ListTile(
                    leading: const Icon(Icons.history_outlined),
                    title: const Text('Automatic backups'),
                    subtitle: const Text(
                      'Saved daily and before anything is deleted',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => AutoBackupsScreen(backups: backups),
                      ),
                    ),
                  ),
                  const Divider(indent: 56),
                ],
                ListTile(
                  leading: const Icon(Icons.save_alt_outlined),
                  title: const Text('Save a copy elsewhere'),
                  subtitle: const Text(
                    'Send a backup file to Drive, email or WhatsApp',
                  ),
                  onTap: () => _run(() => shareBackup(store)),
                ),
                const Divider(indent: 56),
                ListTile(
                  leading: const Icon(Icons.table_chart_outlined),
                  title: const Text('Export attendance registers'),
                  subtitle: const Text(
                    'Present or absent for each day, one Excel sheet per '
                    'month',
                  ),
                  enabled: hasSessions,
                  onTap: () => _run(() => shareRegisters(store)),
                ),
                const Divider(indent: 56),
                ListTile(
                  leading: const Icon(Icons.settings_backup_restore_outlined),
                  title: const Text('Restore from a file'),
                  subtitle: const Text('Bring back a copy you saved'),
                  onTap: _restoreFromFile,
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.lock_outline,
                    size: 16,
                    color: context.colors.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Everything stays on this phone and works offline. '
                      'Huddle keeps its own backups, and your phone\'s Google '
                      'backup includes them too. For extra peace of mind, '
                      'save a copy elsewhere now and then.',
                      style: context.text.bodySmall?.copyWith(height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            Center(
              child: Column(
                children: [
                  const Basketball(size: 28),
                  const SizedBox(height: 8),
                  Text(
                    'HUDDLE',
                    style: context.text.labelSmall?.copyWith(
                      fontSize: 14,
                      letterSpacing: 4,
                    ),
                  ),
                  Text(
                    'Version 1.1 · Made for coaches',
                    style: context.text.bodySmall,
                  ),
                ],
              ),
            ),
            if (_busy)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              ),
          ],
        ),
      ),
    );
  }
}

/// Asks before replacing everything with [snapshot]. The current data is
/// saved as a safety copy first, so this can always be undone.
Future<bool> confirmRestore(BuildContext context, Snapshot snapshot) async {
  final store = context.readStore;
  final ok = await confirm(
    context,
    title: 'Restore this backup?',
    message:
        'It has ${plural(snapshot.squads.length, 'squad')}, '
        '${plural(snapshot.players.length, 'player')} and '
        '${plural(snapshot.sessions.length, 'session')}.\n\n'
        'What\'s on the phone now will be replaced. Don\'t worry: it\'s kept '
        'as an automatic backup first, so you can switch back.',
    action: 'Restore',
  );
  if (!ok) return false;
  await store.replaceAll(snapshot);
  if (context.mounted) showSnack(context, 'Backup restored');
  return true;
}

class AutoBackupsScreen extends StatefulWidget {
  const AutoBackupsScreen({super.key, required this.backups});

  final AutoBackups backups;

  @override
  State<AutoBackupsScreen> createState() => _AutoBackupsScreenState();
}

class _AutoBackupsScreenState extends State<AutoBackupsScreen> {
  late Future<List<AutoBackupFile>> _files = _load();

  Future<List<AutoBackupFile>> _load() async {
    // Make sure today's copy reflects the latest changes first.
    await widget.backups.daily(context.readStore);
    return widget.backups.list();
  }

  Future<void> _restore(AutoBackupFile file) async {
    final Snapshot snapshot;
    try {
      snapshot = await file.read();
    } catch (_) {
      if (mounted) showSnack(context, 'That backup couldn\'t be read.');
      return;
    }
    if (!mounted) return;
    final restored = await confirmRestore(context, snapshot);
    if (restored && mounted) {
      setState(() => _files = widget.backups.list());
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.store;
    return Scaffold(
      appBar: AppBar(title: const Text('Automatic backups')),
      body: FutureBuilder<List<AutoBackupFile>>(
        future: _files,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final files = snap.data!;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
            children: [
              Text(
                'Huddle saves a copy every day (keeping two weeks) and right '
                'before anything is deleted or replaced. Tap one to bring it '
                'back.',
                style: context.text.bodyMedium?.copyWith(
                  color: context.colors.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              if (files.isEmpty)
                const EmptyState(
                  title: 'No backups yet',
                  message:
                      'The first one is made as soon as you add a squad or '
                      'a player.',
                )
              else
                Card(
                  child: Column(
                    children: [
                      for (var i = 0; i < files.length; i++) ...[
                        if (i > 0) const Divider(indent: 56),
                        ListTile(
                          leading: Icon(
                            files[i].kind == AutoBackupKind.daily
                                ? Icons.event_repeat_outlined
                                : Icons.health_and_safety_outlined,
                            color: files[i].kind == AutoBackupKind.daily
                                ? null
                                : Brand.orange,
                          ),
                          title: Text(files[i].description),
                          subtitle: Text(_when(files[i].time, store)),
                          trailing: const Icon(Icons.restore),
                          onTap: () => _restore(files[i]),
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  String _when(DateTime t, HuddleStore store) {
    final day = fmtRelative(t, store.today);
    return '$day · ${DateFormat.jm().format(t)}';
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Card(child: Column(children: children)),
    );
  }
}
