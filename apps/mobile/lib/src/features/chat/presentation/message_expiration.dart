import 'dart:math';

bool isMessageExpired(DateTime? expiresAt, {DateTime? now}) {
  if (expiresAt == null) {
    return false;
  }

  final current = now ?? DateTime.now();
  return !expiresAt.isAfter(current);
}

String formatMessageExpiry(DateTime expiresAt, {DateTime? now}) {
  final current = now ?? DateTime.now();
  if (isMessageExpired(expiresAt, now: current)) {
    return 'Expired';
  }

  final remaining = expiresAt.difference(current);
  if (remaining.inSeconds < 60) {
    return 'Expires in ${max(1, remaining.inSeconds)}s';
  }

  if (remaining.inMinutes < 60) {
    return 'Expires in ${remaining.inMinutes}m';
  }

  if (remaining.inHours < 24) {
    return 'Expires in ${remaining.inHours}h';
  }

  return 'Expires in ${remaining.inDays}d';
}
