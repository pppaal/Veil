import 'dart:math';

// [now] is the messenger's expiry clock (VeilMessengerController.expiryNow),
// not the device clock: a device whose clock runs fast would otherwise hide a
// message the relay still keeps.
bool isMessageExpired(DateTime? expiresAt, {required DateTime now}) {
  if (expiresAt == null) {
    return false;
  }

  return !expiresAt.isAfter(now);
}

String formatMessageExpiry(DateTime expiresAt, {required DateTime now}) {
  if (isMessageExpired(expiresAt, now: now)) {
    return 'Expired';
  }

  final remaining = expiresAt.difference(now);
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
