import 'package:flutter/material.dart';

import '../../../core/crypto/crypto_engine.dart';
import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_ui.dart';
import '../../conversations/data/conversation_models.dart';
import '../../conversations/data/messenger/local_notice.dart';

/// What a message that did not open shows instead of a bubble: an icon and
/// this app's own words for the outcome. It is chosen by status alone, so no
/// text a peer sends can look like it, and nothing the peer sent is shown.
class DecryptFailureChip extends StatelessWidget {
  const DecryptFailureChip({super.key, required this.status});

  final DecryptStatus status;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.veilPalette;
    final (icon, label) = switch (status) {
      DecryptStatus.replayed => (Icons.history_toggle_off_rounded, l10n.chatDecryptReplayed),
      DecryptStatus.awaitingKey => (Icons.key_off_outlined, l10n.chatDecryptAwaitingKey),
      DecryptStatus.sessionMissing => (Icons.sync_problem_outlined, l10n.chatDecryptSessionMissing),
      DecryptStatus.identityRejected => (Icons.gpp_bad_outlined, l10n.chatDecryptIdentityRejected),
      DecryptStatus.ok || DecryptStatus.legacyUnauthenticated || DecryptStatus.failed =>
        (Icons.lock_outline_rounded, l10n.chatDecryptFailed),
    };
    return Semantics(
      label: label,
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: VeilSpace.sm, vertical: VeilSpace.xs),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(VeilRadius.pill),
          color: palette.surfaceOverlay,
          border: Border.all(color: palette.strokeStrong),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: VeilIconSize.sm, color: palette.warning),
            const SizedBox(width: VeilSpace.xs),
            Flexible(
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: palette.textMuted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The text of a system row. Codes are translated only on rows this device
/// inserted itself; a peer's system message is shown as it was written.
String systemNoticeText(AppLocalizations l10n, ChatMessage message, String body) {
  if (!message.isLocalNotice) return body;
  return switch (body) {
    LocalNoticeCodes.identityChanged => l10n.chatNoticeIdentityChanged,
    LocalNoticeCodes.identityNewDevice => l10n.chatNoticeIdentityNewDevice,
    LocalNoticeCodes.senderKeysKept => l10n.chatNoticeSenderKeysKept,
    _ => body,
  };
}
