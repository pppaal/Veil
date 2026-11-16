import 'package:flutter/material.dart';

import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_ui.dart';

/// What takes the composer's place while a chat is searched: which hit is
/// shown ("1 of 2"), and the arrows to the one before and after it, as in
/// Signal and Telegram. "No results" when the query matched nothing.
class ChatSearchBar extends StatelessWidget {
  const ChatSearchBar({
    super.key,
    required this.hasQuery,
    required this.searching,
    required this.count,
    required this.index,
    required this.onOlder,
    required this.onNewer,
  });

  final bool hasQuery;
  final bool searching;

  /// How many messages matched, and which is shown (0 is the oldest).
  final int count;
  final int index;
  final VoidCallback onOlder;
  final VoidCallback onNewer;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.veilPalette;
    final status = !hasQuery
        ? ''
        : searching
            ? l10n.chatSearchSearching
            : count == 0
                ? l10n.chatSearchEmptyTitle
                : l10n.chatSearchPosition(index + 1, count);
    return Padding(
      padding: const EdgeInsets.fromLTRB(VeilSpace.md, 6, VeilSpace.xs, 6),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              liveRegion: true,
              child: Text(status, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: palette.textMuted)),
            ),
          ),
          IconButton(
            tooltip: l10n.chatSearchOlderTooltip,
            onPressed: count > 0 && index > 0 ? onOlder : null,
            icon: const Icon(Icons.keyboard_arrow_up),
          ),
          IconButton(
            tooltip: l10n.chatSearchNewerTooltip,
            onPressed: count > 0 && index < count - 1 ? onNewer : null,
            icon: const Icon(Icons.keyboard_arrow_down),
          ),
        ],
      ),
    );
  }
}
