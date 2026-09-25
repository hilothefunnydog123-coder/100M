const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String formatTime(DateTime d) {
  final l = d.toLocal();
  final hour = l.hour % 12 == 0 ? 12 : l.hour % 12;
  final minute = l.minute.toString().padLeft(2, '0');
  return '$hour:$minute ${l.hour < 12 ? 'AM' : 'PM'}';
}

/// "Today, 3:42 PM", "Yesterday", or "Sep 25, 2026".
String formatDate(DateTime d, {DateTime? now}) {
  final l = d.toLocal();
  final today = (now ?? DateTime.now()).toLocal();
  final day = DateTime(l.year, l.month, l.day);
  final diff = DateTime(today.year, today.month, today.day).difference(day);
  if (diff.inDays == 0) return 'Today, ${formatTime(l)}';
  if (diff.inDays == 1) return 'Yesterday';
  return '${_months[l.month - 1]} ${l.day}, ${l.year}';
}

/// "in 5 days", "tomorrow", "today", or "3 days ago".
String relativeDays(DateTime d, {DateTime? now}) {
  final base = (now ?? DateTime.now()).toLocal();
  final a = DateTime(base.year, base.month, base.day);
  final l = d.toLocal();
  final days = DateTime(l.year, l.month, l.day).difference(a).inDays;
  if (days == 0) return 'today';
  if (days == 1) return 'tomorrow';
  if (days == -1) return 'yesterday';
  return days > 0 ? 'in $days days' : '${-days} days ago';
}
