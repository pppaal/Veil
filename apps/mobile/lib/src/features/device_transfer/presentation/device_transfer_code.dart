import 'package:intl/intl.dart';

import '../../../l10n/generated/app_localizations.dart';

/// The two parts of a transfer code: the session the old device opened and
/// the token that claims it.
class ParsedTransferCode {
  const ParsedTransferCode({required this.sessionId, required this.transferToken});

  final String sessionId;
  final String transferToken;
}

/// What a copied transfer code starts with. The API takes the session and
/// the token apart, so the prefix only marks a pasted text as a code.
const transferCodePrefix = 'VEIL_TRANSFER::';

/// The code as the old phone's box shows it: `<session>::<token>`, without
/// [transferCodePrefix], which means nothing to the person reading it.
/// "Copy code" still copies the whole code.
String transferCodeForDisplay(String code) =>
    code.startsWith(transferCodePrefix) ? code.substring(transferCodePrefix.length) : code;

/// Reads a transfer code as the old device copies it
/// (`VEIL_TRANSFER::<session>::<token>`), as its box shows it
/// (`<session>::<token>`), or as two lines starting with "session" and
/// "token"; null for anything else.
ParsedTransferCode? parseTransferCode(String raw) {
  if (raw.isEmpty) {
    return null;
  }

  final bare = transferCodeForDisplay(raw);
  final parts = bare.split('::');
  if (parts.length == 2 && parts.every((part) => part.isNotEmpty && !part.contains(RegExp(r'\s')))) {
    return ParsedTransferCode(sessionId: parts[0], transferToken: parts[1]);
  }

  final lines = raw.split('\n').map((line) => line.trim()).where((line) => line.isNotEmpty).toList();
  if (lines.length >= 2) {
    final sessionLine = lines.firstWhere(
      (line) => line.toLowerCase().startsWith('session '),
      orElse: () => '',
    );
    final tokenLine = lines.firstWhere(
      (line) => line.toLowerCase().startsWith('token '),
      orElse: () => '',
    );
    if (sessionLine.isNotEmpty && tokenLine.isNotEmpty) {
      return ParsedTransferCode(
        sessionId: sessionLine.substring('session '.length).trim(),
        transferToken: tokenLine.substring('token '.length).trim(),
      );
    }
  }

  return null;
}

/// When [expiresAt] is, seen from [now]: "now", "in 40s", "in 4m", or the
/// day and time once it is an hour or more away.
String formatTransferExpiry(DateTime expiresAt, DateTime now, AppLocalizations l10n) {
  if (!expiresAt.isAfter(now)) {
    return l10n.deviceTransferExpiryNow;
  }

  final remaining = expiresAt.difference(now);
  if (remaining.inMinutes < 1) {
    return l10n.deviceTransferExpiryInSeconds(remaining.inSeconds);
  }
  if (remaining.inHours < 1) {
    return l10n.deviceTransferExpiryInMinutes(remaining.inMinutes);
  }

  return l10n.deviceTransferExpiryAt(DateFormat.MMMd(l10n.localeName).add_Hm().format(expiresAt.toLocal()));
}
