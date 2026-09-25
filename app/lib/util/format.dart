const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String formatTime(DateTime d) {
  final l = d.toLocal();
  final hour = l.hour % 12 == 0 ? 12 : l.hour % 12;
  final minute = l.minute.toString().padLeft(2, '0');
  return '$hour:$minute ${l.hour < 12 ? 'AM' : 'PM'}';
}

/// "Sep 25, 2026".
String formatDay(DateTime d) {
  final l = d.toLocal();
  return '${_months[l.month - 1]} ${l.day}, ${l.year}';
}

/// "Sep 25".
String formatShortDay(DateTime d) {
  final l = d.toLocal();
  return '${_months[l.month - 1]} ${l.day}';
}

/// "just now", "5 min ago", "3 hr ago", "yesterday", "4 days ago", or a date.
String timeAgo(DateTime d, {required DateTime now}) {
  final diff = now.difference(d);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours} hr ago';
  if (diff.inDays == 1) return 'yesterday';
  if (diff.inDays < 7) return '${diff.inDays} days ago';
  return formatShortDay(d);
}

/// "12.5" or "12" for hours and percentages.
String trimNumber(double v, {int decimals = 1}) {
  final s = v.toStringAsFixed(decimals);
  return s.contains('.') ? s.replaceFirst(RegExp(r'\.?0+$'), '') : s;
}

/// "4:05" for an elapsed duration.
String formatElapsed(Duration d) =>
    '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
