import 'dart:math';

import '../../../l10n/generated/app_localizations.dart';

// [now] is the messenger's expiry clock (VeilMessengerController.expiryNow),
// not the device clock: a device whose clock runs fast would otherwise hide a
// message the relay still keeps.
bool isMessageExpired(DateTime? expiresAt, {required DateTime now}) {
  if (expiresAt == null) {
    return false;
  }

  return !expiresAt.isAfter(now);
}

/// "Expires in 5m", in the user's language, or "Expired".
String formatMessageExpiry(AppLocalizations l10n, DateTime expiresAt, {required DateTime now}) {
  if (isMessageExpired(expiresAt, now: now)) {
    return l10n.chatExpiryExpired;
  }

  final remaining = expiresAt.difference(now);
  if (remaining.inSeconds < 60) {
    return l10n.chatExpirySeconds(max(1, remaining.inSeconds));
  }

  if (remaining.inMinutes < 60) {
    return l10n.chatExpiryMinutes(remaining.inMinutes);
  }

  if (remaining.inHours < 24) {
    return l10n.chatExpiryHours(remaining.inHours);
  }

  return l10n.chatExpiryDays(remaining.inDays);
}
