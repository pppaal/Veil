import 'package:flutter/material.dart';

import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_ui.dart';

/// What a 1:1 shows in place of its composer while the user has the peer
/// blocked: one line saying so, and Unblock. Nothing can be sent until then:
/// the server refuses it.
class BlockedComposerLine extends StatelessWidget {
  const BlockedComposerLine({super.key, required this.name, required this.onUnblock});

  /// What the chat calls the blocked peer, which the line names: their
  /// nickname, or their handle with its "@".
  final String name;
  final VoidCallback onUnblock;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final palette = context.veilPalette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(VeilSpace.md, VeilSpace.xxs, VeilSpace.xs, VeilSpace.xxs),
      child: Row(
        children: [
          Expanded(
            child: Text(
              l10n.blockedComposerLine(name),
              style: theme.textTheme.bodyMedium?.copyWith(color: palette.textMuted),
            ),
          ),
          const SizedBox(width: VeilSpace.xs),
          TextButton(onPressed: onUnblock, child: Text(l10n.unblockAction)),
        ],
      ),
    );
  }
}
