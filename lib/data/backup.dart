import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'models.dart';
import 'store.dart';

String encodeBackup(Snapshot snapshot) =>
    const JsonEncoder.withIndent(' ').convert(snapshot.toJson());

Snapshot decodeBackup(String text) {
  final Object? json;
  try {
    json = jsonDecode(text);
  } on FormatException {
    throw const FormatException('This file is not a Huddle backup.');
  }
  if (json is! Map) {
    throw const FormatException('This file is not a Huddle backup.');
  }
  return Snapshot.fromJson(json.cast<String, Object?>());
}

String _csvCell(Object? value) {
  final s = '${value ?? ''}';
  if (s.contains(RegExp(r'[",\n\r]'))) return '"${s.replaceAll('"', '""')}"';
  return s;
}

String _csvRow(Iterable<Object?> cells) => cells.map(_csvCell).join(',');

/// The attendance register for one squad: one row per player, one column
/// per training day, and each cell just "Present" or "Absent". Late counts
/// as present and excused as absent. The cell is empty if the player wasn't
/// on the register that day (e.g. they joined the squad later).
String buildRegisterCsv(HuddleStore store, Squad squad) {
  // Oldest day first. A squad normally has one session a day, but if there
  // are more, being at any of them counts as present for that day.
  final days = <DateTime, List<Session>>{};
  for (final s in store.sessionsOf(squad.id).reversed) {
    days.putIfAbsent(dateOnly(s.date), () => []).add(s);
  }
  final playerIds = <String>{
    for (final sessions in days.values)
      for (final s in sessions) ...store.recordsOf(s.id).keys,
    for (final p in store.membersOf(squad.id)) p.id,
  };
  final players =
      playerIds.map(store.player).whereType<Player>().toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  String cell(List<Session> sessions, String playerId) {
    final statuses = [
      for (final s in sessions) ?store.statusOf(s.id, playerId),
    ];
    if (statuses.isEmpty) return '';
    return statuses.any((s) => s.attended) ? 'Present' : 'Absent';
  }

  final fmt = DateFormat('yyyy-MM-dd');
  final buffer = StringBuffer()
    ..writeln(
      _csvRow(['Player', for (final day in days.keys) fmt.format(day)]),
    );
  for (final pl in players) {
    buffer.writeln(
      _csvRow([
        pl.name,
        for (final sessions in days.values) cell(sessions, pl.id),
      ]),
    );
  }
  return buffer.toString();
}

String _slug(String s) {
  final slug = s
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');
  return slug.isEmpty ? 'squad' : slug;
}

Future<Directory> _exportDir() async {
  final dir = Directory(
    p.join((await getTemporaryDirectory()).path, 'exports'),
  );
  if (dir.existsSync()) dir.deleteSync(recursive: true);
  return dir.create(recursive: true);
}

/// Shares one register CSV per squad through the system share sheet.
Future<void> shareRegisters(HuddleStore store) async {
  final dir = await _exportDir();
  final stamp = DateFormat('yyyy-MM-dd').format(store.now);
  final files = <XFile>[];
  for (final squad in store.allSquads) {
    if (store.sessionsOf(squad.id).isEmpty) continue;
    final file = File(p.join(dir.path, '${_slug(squad.name)}-$stamp.csv'));
    // BOM so Excel opens accented names correctly.
    await file.writeAsString('﻿${buildRegisterCsv(store, squad)}');
    files.add(XFile(file.path, mimeType: 'text/csv'));
  }
  if (files.isEmpty) return;
  await SharePlus.instance.share(
    ShareParams(files: files, subject: 'Attendance registers ($stamp)'),
  );
}

/// Shares a full backup file the coach can keep somewhere safe.
Future<void> shareBackup(HuddleStore store) async {
  await store.flush();
  final dir = await _exportDir();
  final stamp = DateFormat('yyyy-MM-dd').format(store.now);
  final file = File(p.join(dir.path, 'huddle-backup-$stamp.json'));
  await file.writeAsString(encodeBackup(store.snapshot()));
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile(file.path, mimeType: 'application/json')],
      subject: 'Huddle backup ($stamp)',
    ),
  );
}

/// Lets the coach pick a backup file. Returns null if they cancelled.
/// Throws [FormatException] if the file isn't a valid backup.
Future<Snapshot?> pickBackup() async {
  final files = await FilePicker.pickFiles(type: FileType.any);
  if (files.isEmpty) return null;
  final text = await files.first.xFile.readAsString();
  return decodeBackup(text);
}
