import 'package:flutter/material.dart';

import '../../../core/crypto/crypto_engine.dart';
import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_ui.dart';
import '../../conversations/data/conversation_models.dart';
import 'decrypt_status_view.dart';

/// A system line, centred in the chat in small muted type with nothing
/// around it: a notice this device inserted itself, or a peer's system
/// message that authenticated as one.
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
    return LayoutBuilder(
      builder: (context, constraints) => Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: constraints.maxWidth * 0.8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: VeilSpace.xxs),
            child: Text(
              systemNoticeText(AppLocalizations.of(context), message, notice.body),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: palette.textMuted),
            ),
          ),
        ),
      ),
    );
  }
}
