import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'backup.dart';
import 'models.dart';
import 'store.dart';

enum AutoBackupKind { daily, safety }

class AutoBackupFile {
  AutoBackupFile(this.file, this.kind, this.time, this.reason);

  final File file;
  final AutoBackupKind kind;
  final DateTime time;

  /// Why a safety copy was made ("delete-squad", "restore", ...).
  final String? reason;

  String get description => switch (reason) {
    null => 'Daily backup',
    'delete-squad' => 'Before deleting a squad',
    'delete-player' => 'Before deleting a player',
    'delete-session' => 'Before deleting a session',
    'restore' => 'Before restoring a backup',
    'remove-demo' => 'Before removing the demo data',
    final other => 'Before $other',
  };

  Future<Snapshot> read() async => decodeBackup(await file.readAsString());
}

/// Automatic, on-device backups so a slip of the finger never costs a season
/// of attendance:
///
/// * a **daily** copy (the last [keepDaily] days), refreshed whenever the app
///   goes to the background, and
/// * a **safety** copy taken right before anything is deleted or replaced
///   (the last [keepSafety]).
///
/// Files live in the app's private storage, which Android's own phone backup
/// also includes.
class AutoBackups {
  AutoBackups(this.dir);

  final Directory dir;

  static const keepDaily = 14;
  static const keepSafety = 10;

  int? _savedRevision;

  static Future<AutoBackups> open() async {
    final base = await getApplicationSupportDirectory();
    return AutoBackups(Directory(p.join(base.path, 'backups')));
  }

  /// Connects to [store] so safety copies happen automatically.
  void attach(HuddleStore store) {
    store.beforeDestructive = (before, reason) => safety(before, reason);
  }

  static String _two(int n) => n.toString().padLeft(2, '0');

  static String _stamp(DateTime t) =>
      '${t.year}${_two(t.month)}${_two(t.day)}-'
      '${_two(t.hour)}${_two(t.minute)}${_two(t.second)}-'
      '${t.millisecond.toString().padLeft(3, '0')}';

  static bool _isEmpty(Snapshot s) => s.squads.isEmpty && s.players.isEmpty;

  /// Writes atomically: a crash mid-write never leaves a broken backup.
  Future<void> _write(String name, Snapshot snapshot) async {
    await dir.create(recursive: true);
    final target = File(p.join(dir.path, name));
    final temp = File('${target.path}.tmp');
    await temp.writeAsString(encodeBackup(snapshot), flush: true);
    await temp.rename(target.path);
  }

  /// Refreshes today's daily backup if anything changed since the last one.
  Future<void> daily(HuddleStore store) async {
    try {
      final today = store.today;
      final name = 'daily-${dateKey(today)}.json';
      final exists = File(p.join(dir.path, name)).existsSync();
      if (exists && _savedRevision == store.revision) return;
      await store.flush();
      final snapshot = store.snapshot();
      if (_isEmpty(snapshot)) return; // never replace a backup with nothing
      final revision = store.revision;
      await _write(name, snapshot);
      _savedRevision = revision;
      await _prune();
    } catch (e) {
      debugPrint('Huddle: daily backup failed: $e');
    }
  }

  /// Keeps a copy of [before] ahead of a destructive change.
  Future<void> safety(Snapshot before, String reason) async {
    if (_isEmpty(before)) return;
    final slug = reason.replaceAll(RegExp('[^a-z0-9-]'), '');
    var time = DateTime.now();
    String name() => 'safety-${_stamp(time)}-$slug.json';
    // Never overwrite an earlier (more complete) safety copy.
    while (File(p.join(dir.path, name())).existsSync()) {
      time = time.add(const Duration(milliseconds: 1));
    }
    await _write(name(), before);
    await _prune();
  }

  /// All backups, newest first.
  Future<List<AutoBackupFile>> list() async {
    if (!dir.existsSync()) return [];
    final result = <AutoBackupFile>[];
    await for (final entity in dir.list()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      final parsed = _parse(entity);
      if (parsed != null) result.add(parsed);
    }
    result.sort((a, b) => b.time.compareTo(a.time));
    return result;
  }

  static final _dailyName = RegExp(r'^daily-(\d{4})-(\d{2})-(\d{2})\.json$');
  static final _safetyName = RegExp(
    r'^safety-(\d{4})(\d{2})(\d{2})-(\d{2})(\d{2})(\d{2})-(\d{3})-'
    r'([a-z0-9-]+)\.json$',
  );

  static AutoBackupFile? _parse(File file) {
    final name = p.basename(file.path);
    final d = _dailyName.firstMatch(name);
    if (d != null) {
      // Daily files are refreshed through the day; use the file's time.
      return AutoBackupFile(
        file,
        AutoBackupKind.daily,
        file.lastModifiedSync(),
        null,
      );
    }
    final s = _safetyName.firstMatch(name);
    if (s != null) {
      int g(int i) => int.parse(s.group(i)!);
      return AutoBackupFile(
        file,
        AutoBackupKind.safety,
        DateTime(g(1), g(2), g(3), g(4), g(5), g(6), g(7)),
        s.group(8),
      );
    }
    return null;
  }

  Future<void> _prune() async {
    final all = await list();
    for (final kind in AutoBackupKind.values) {
      final keep = kind == AutoBackupKind.daily ? keepDaily : keepSafety;
      final ofKind = all.where((b) => b.kind == kind).toList();
      for (final old in ofKind.skip(keep)) {
        try {
          await old.file.delete();
        } catch (_) {}
      }
    }
  }
}
