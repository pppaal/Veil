import 'package:flutter/material.dart';

import '../../../core/crypto/crypto_engine.dart';
import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_ui.dart';
import '../../conversations/data/conversation_models.dart';
import 'decrypt_status_view.dart';

/// A system row, centred in the chat: a notice this device inserted itself,
/// or a peer's system message that authenticated as one.
class SystemNoticeBubble extends StatelessWidget {
  const SystemNoticeBubble({
    super.key,
    required this.message,
    required this.notice,
  });

  final ChatMessage message;
  final DecryptedMessage notice;

  @override
  Widget build(BuildContext context) {
    final palette = context.veilPalette;
    final theme = Theme.of(context);
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420),
        padding: const EdgeInsets.symmetric(
          horizontal: VeilSpace.md,
          vertical: VeilSpace.sm,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(VeilRadius.pill),
          color: palette.surfaceOverlay,
          border: Border.all(color: palette.strokeStrong),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              message.isLocalNotice ? Icons.gpp_maybe_outlined : Icons.camera_alt_outlined,
              size: VeilIconSize.sm,
              color: palette.warning,
            ),
            const SizedBox(width: VeilSpace.sm),
            Flexible(
              child: Text(
                systemNoticeText(AppLocalizations.of(context), message, notice.body),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: palette.textMuted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
