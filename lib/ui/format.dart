import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/models.dart';

const weekdayLetters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
const weekdayShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// "Thursday, 2 October"
String fmtLong(DateTime d) => DateFormat('EEEE, d MMMM').format(d);

/// "Thu 2 Oct"
String fmtShort(DateTime d) => DateFormat('EEE d MMM').format(d);

/// "Thu 2 Oct 2025" — only adds the year when it isn't this year.
String fmtShortWithYear(DateTime d, DateTime today) => d.year == today.year
    ? fmtShort(d)
    : DateFormat('EEE d MMM yyyy').format(d);

/// "October 2026"
String fmtMonth(DateTime d) => DateFormat('MMMM yyyy').format(d);

/// "Today", "Yesterday", "Tuesday", or "Thu 2 Oct".
String fmtRelative(DateTime day, DateTime today) {
  final diff = dateOnly(today).difference(dateOnly(day)).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  if (diff == -1) return 'Tomorrow';
  if (diff > 1 && diff < 7) return DateFormat('EEEE').format(day);
  return fmtShortWithYear(day, today);
}

/// Like [fmtRelative] but for use mid-sentence ("last here yesterday").
String fmtRelativeInline(DateTime day, DateTime today) {
  final rel = fmtRelative(day, today);
  return switch (rel) {
    'Today' || 'Yesterday' || 'Tomorrow' => rel.toLowerCase(),
    _ => rel,
  };
}

/// "Tue · Sat", "Weekdays", "Every day", or "No set days".
String fmtWeekdays(Set<int> days) {
  if (days.isEmpty) return 'No set days';
  if (days.length == 7) return 'Every day';
  if (days.length == 5 && !days.contains(6) && !days.contains(7)) {
    return 'Weekdays';
  }
  if (days.length == 2 && days.contains(6) && days.contains(7)) {
    return 'Weekends';
  }
  final sorted = days.toList()..sort();
  return sorted.map((d) => weekdayShort[d - 1]).join(' · ');
}

String fmtMinutes(BuildContext context, int minutes) =>
    TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60).format(context);

String greeting(DateTime now) {
  if (now.hour < 12) return 'Good morning';
  if (now.hour < 17) return 'Good afternoon';
  return 'Good evening';
}

String plural(int n, String one, [String? many]) =>
    '$n ${n == 1 ? one : (many ?? '${one}s')}';
