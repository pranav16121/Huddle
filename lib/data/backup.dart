import 'dart:convert';
import 'dart:io';

import 'package:excel/excel.dart'
    show
        CellIndex,
        CellStyle,
        CellValue,
        Excel,
        HorizontalAlign,
        IntCellValue,
        TextCellValue;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/widgets.dart' show StringCharacters;
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

/// A sheet tab name Excel accepts: at most 31 characters, none of
/// : \ / ? * [ ], no apostrophe at either end, and unique ignoring case.
String _sheetName(String squad, String month, Set<String> taken) {
  final clean = squad.replaceAll(RegExp(r'[:\\/?*\[\]\s]+'), ' ');
  for (var n = 1; ; n++) {
    final tail = '${n == 1 ? '' : ' $n'} - $month';
    var head = '';
    for (final c in clean.characters) {
      if (head.length + c.length > 31 - tail.length) break;
      head += c;
    }
    head = head.replaceAll(RegExp(r"^[ ']+|[ ']+$"), '');
    final name = '${head.isEmpty ? 'Squad' : head}$tail';
    if (taken.add(name.toLowerCase())) return name;
  }
}

/// The attendance workbook: one sheet per month that has at least one
/// session, with one row per player, one column per training day and a
/// final TOTAL ATTENDED column counting the P's. Each day is just P
/// (present) or A (late, excused or absent). The cell is empty if the player
/// wasn't on the register that day (e.g. they joined the squad later).
///
/// Every squad gets its own sheets; when more than one squad has sessions,
/// the tab names start with the squad ("U10 - October 2026"). Returns null if
/// there are no sessions at all.
List<int>? buildAttendanceWorkbook(HuddleStore store) {
  final squads = [
    for (final squad in store.allSquads)
      if (store.sessionsOf(squad.id).isNotEmpty) squad,
  ];
  if (squads.isEmpty) return null;

  final excel = Excel.createExcel();
  final blank = excel.getDefaultSheet()!;
  final taken = <String>{};
  String? first;
  final monthFmt = DateFormat('MMMM yyyy');
  final dayFmt = DateFormat('dd/MM/yyyy');
  final bold = CellStyle(bold: true);
  final centred = CellStyle(horizontalAlign: HorizontalAlign.Center);
  final heading = CellStyle(
    bold: true,
    horizontalAlign: HorizontalAlign.Center,
  );

  for (final squad in squads) {
    // Oldest day first, grouped by month. A squad normally has one session a
    // day, but if there are more, being present at any of them counts as
    // present for that day.
    final months = <DateTime, Map<DateTime, List<Session>>>{};
    for (final s in store.sessionsOf(squad.id).reversed) {
      final day = dateOnly(s.date);
      months
          .putIfAbsent(DateTime(day.year, day.month), () => {})
          .putIfAbsent(day, () => [])
          .add(s);
    }

    for (final MapEntry(key: month, value: days) in months.entries) {
      final playerIds = <String>{
        for (final sessions in days.values)
          for (final s in sessions) ...store.recordsOf(s.id).keys,
        for (final p in store.membersOf(squad.id)) p.id,
      };
      final players = playerIds.map(store.player).whereType<Player>().toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

      String mark(List<Session> sessions, String playerId) {
        final statuses = [
          for (final s in sessions) ?store.statusOf(s.id, playerId),
        ];
        if (statuses.isEmpty) return '';
        return statuses.contains(AttendanceStatus.present) ? 'P' : 'A';
      }

      final title = monthFmt.format(month);
      final name = squads.length == 1
          ? title
          : _sheetName(squad.name, title, taken);
      first ??= name;
      final sheet = excel[name];
      void put(int row, int col, CellValue value, [CellStyle? style]) =>
          sheet.updateCell(
            CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row),
            value,
            cellStyle: style,
          );

      put(0, 0, TextCellValue('ATTENDANCE REPORT'), bold);
      put(1, 0, TextCellValue(title));
      put(3, 0, TextCellValue('Player'), bold);
      final dates = days.keys.toList();
      for (final (i, day) in dates.indexed) {
        put(3, i + 1, TextCellValue(dayFmt.format(day)), heading);
        sheet.setColumnWidth(i + 1, 12);
      }
      put(3, dates.length + 1, TextCellValue('TOTAL ATTENDED'), heading);
      sheet.setColumnWidth(0, 24);
      sheet.setColumnWidth(dates.length + 1, 16);

      for (final (r, pl) in players.indexed) {
        final marks = [for (final s in days.values) mark(s, pl.id)];
        put(r + 4, 0, TextCellValue(pl.name));
        for (final (i, m) in marks.indexed) {
          if (m.isNotEmpty) put(r + 4, i + 1, TextCellValue(m), centred);
        }
        put(
          r + 4,
          marks.length + 1,
          IntCellValue(marks.where((m) => m == 'P').length),
          centred,
        );
      }
    }
  }

  excel
    ..delete(blank)
    ..setDefaultSheet(first!);
  return excel.encode();
}

Future<Directory> _exportDir() async {
  final dir = Directory(
    p.join((await getTemporaryDirectory()).path, 'exports'),
  );
  if (dir.existsSync()) dir.deleteSync(recursive: true);
  return dir.create(recursive: true);
}

/// Shares the attendance workbook through the system share sheet. It's
/// rebuilt from scratch each time, so it always has every session so far.
Future<void> shareRegisters(HuddleStore store) async {
  final dir = await _exportDir();
  final stamp = DateFormat('yyyy-MM-dd').format(store.now);
  final bytes = buildAttendanceWorkbook(store);
  if (bytes == null) return;
  final file = File(p.join(dir.path, 'Huddle_Attendance.xlsx'));
  await file.writeAsBytes(bytes);
  await SharePlus.instance.share(
    ShareParams(
      files: [
        XFile(
          file.path,
          mimeType:
              'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        ),
      ],
      subject: 'Attendance registers ($stamp)',
    ),
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
