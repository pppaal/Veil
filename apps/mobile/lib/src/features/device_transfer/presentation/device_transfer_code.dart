import '../../../l10n/generated/app_localizations.dart';
import '../../chat/presentation/message_time.dart';
import '../data/device_transfer_controller.dart' show transferCodePrefix;

/// The two parts of a transfer code: the session the old device opened and
/// the token that claims it.
class ParsedTransferCode {
  const ParsedTransferCode({required this.sessionId, required this.transferToken});

  final String sessionId;
  final String transferToken;
}

/// [code] without [transferCodePrefix], which means nothing to the person
/// reading it.
String _withoutPrefix(String code) =>
    code.startsWith(transferCodePrefix) ? code.substring(transferCodePrefix.length) : code;

/// The code as the old phone shows it: `<session>::` on one line and
/// `<token>` on the next, without [transferCodePrefix]. At the default text
/// size each is a UUID that fits a phone 360 wide or wider whole; a larger
/// text size can wrap one at a hyphen, which parseTransferCode reads past as
/// it does any whitespace typed in. "Copy code" still copies the whole code,
/// on one line.
String transferCodeForDisplay(String code) => _withoutPrefix(code).replaceFirst('::', '::\n');

final _whitespace = RegExp(r'\s');

/// Reads a transfer code as the old device copies it
/// (`VEIL_TRANSFER::<session>::<token>`), as it shows it (`<session>::` and
/// `<token>` on two lines), or as typed off it with a space or a line break
/// anywhere, since no id holds one; or as two lines starting with "session"
/// and "token". Null for anything else.
ParsedTransferCode? parseTransferCode(String raw) {
  if (raw.isEmpty) {
    return null;
  }

  final parts = _withoutPrefix(raw.replaceAll(_whitespace, '')).split('::');
  if (parts.length == 2 && parts.every((part) => part.isNotEmpty)) {
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
/// day and time once it is an hour or more away, the time as the phone's
/// 12- or 24-hour setting writes it ([timeFormat]).
String formatTransferExpiry(
  DateTime expiresAt,
  DateTime now,
  AppLocalizations l10n, {
  required MessageTimeFormat timeFormat,
}) {
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

  return timeFormat.dayAndTime(expiresAt, now: now);
}
