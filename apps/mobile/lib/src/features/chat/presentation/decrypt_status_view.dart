import 'package:flutter/material.dart';

import '../../../core/crypto/crypto_engine.dart';
import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_ui.dart';
import '../../conversations/data/conversation_models.dart';
import '../../conversations/data/messenger/local_notice.dart';
import 'disappearing_timer_sheet.dart';

/// What a message that did not open shows in its bubble instead of the
/// text: a small padlock and this app's own words for the outcome, in muted
/// italics. It is chosen by status alone, so no text a peer sends can look
/// like it, and nothing the peer sent is shown.
class DecryptFailureLine extends StatelessWidget {
  const DecryptFailureLine({super.key, required this.status, this.color});

  final DecryptStatus status;

  /// The colour of the line; the muted text colour when null.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final color = this.color ?? context.veilPalette.textMuted;
    final label = switch (status) {
      DecryptStatus.replayed => l10n.chatDecryptReplayed,
      DecryptStatus.awaitingKey => l10n.chatDecryptAwaitingKey,
      DecryptStatus.sessionMissing => l10n.chatDecryptSessionMissing,
      DecryptStatus.identityRejected => l10n.chatDecryptIdentityRejected,
      DecryptStatus.ok || DecryptStatus.legacyUnauthenticated || DecryptStatus.failed => l10n.chatDecryptFailed,
    };
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(color: color, fontStyle: FontStyle.italic);
    return Semantics(
      label: label,
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock_outline, size: VeilIconSize.xs, color: color),
          const SizedBox(width: VeilSpace.xxs),
          Flexible(child: Text(label, style: style)),
        ],
      ),
    );
  }
}

/// The text of a system row. Codes are translated only on rows this device
/// inserted itself; a peer's system message is shown as it was written.
String systemNoticeText(AppLocalizations l10n, ChatMessage message, String body) {
  if (!message.isLocalNotice) return message.isMine ? _ownSystemText(l10n, body) : body;
  final timer = _timerNoticeText(l10n, body);
  if (timer != null) return timer;
  return switch (body) {
    LocalNoticeCodes.identityChanged => l10n.chatNoticeIdentityChanged,
    LocalNoticeCodes.identityNewDevice => l10n.chatNoticeIdentityNewDevice,
    LocalNoticeCodes.senderKeysKept => l10n.chatNoticeSenderKeysKept,
    LocalNoticeCodes.groupMemberAdded => l10n.chatNoticeGroupMemberAdded,
    LocalNoticeCodes.groupMemberRemoved => l10n.chatNoticeGroupMemberRemoved,
    _ => body,
  };
}

// A timer change this device noted (LocalNoticeCodes.timerSet...), or null.
String? _timerNoticeText(AppLocalizations l10n, String body) {
  final colon = body.indexOf(':');
  if (colon < 0) return null;
  final code = body.substring(0, colon);
  if (code != LocalNoticeCodes.timerSet && code != LocalNoticeCodes.timerSetByYou) return null;
  final seconds = int.tryParse(body.substring(colon + 1));
  final byYou = code == LocalNoticeCodes.timerSetByYou;
  if (seconds == null) return byYou ? l10n.chatNoticeTimerOffByYou : l10n.chatNoticeTimerOff;
  final duration = disappearingTimerLabel(l10n, Duration(seconds: seconds));
  return byYou ? l10n.chatNoticeTimerSetByYou(duration) : l10n.chatNoticeTimerSet(duration);
}

// The user's own system message, as this device sent it: a screenshot
// notice reads "You took a screenshot" here, whatever its sent words.
String _ownSystemText(AppLocalizations l10n, String body) =>
    isScreenshotNotice(l10n, body) ? l10n.chatScreenshotSelfNotice : body;

/// Whether [body] is the screenshot notice this app sends ("@sam took a
/// screenshot"), read off the same ARB sentence that wrote it.
bool isScreenshotNotice(AppLocalizations l10n, String body) {
  const mark = '\u0000';
  final parts = l10n.chatScreenshotSystemNotice(mark).split(mark);
  if (parts.length != 2) return false;
  return body.length > parts.first.length + parts.last.length &&
      body.startsWith(parts.first) &&
      body.endsWith(parts.last);
}
