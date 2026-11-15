import 'package:flutter/material.dart';

import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_ui.dart';
import '../../conversations/data/conversation_models.dart';

/// The reactions under a message, one chip per emoji with its count, the
/// most used first. A chip this user added to is highlighted, and a tap on
/// one adds or withdraws this user's reaction. Each chip takes a tap over
/// 44 px, more than the pill it draws.
class ReactionChipsRow extends StatelessWidget {
  const ReactionChipsRow({
    super.key,
    required this.message,
    required this.myUserId,
    required this.onChipTap,
  });

  final ChatMessage message;
  final String? myUserId;
  final ValueChanged<String> onChipTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.veilPalette;
    final grouped = <String, List<Reaction>>{};
    for (final reaction in message.reactions) {
      grouped.putIfAbsent(reaction.emoji, () => []).add(reaction);
    }
    if (grouped.isEmpty) {
      return const SizedBox.shrink();
    }

    final entries = grouped.entries.toList()
      ..sort((a, b) => b.value.length.compareTo(a.value.length));

    return Wrap(
      children: [
        for (final entry in entries)
          _ReactionChip(
            emoji: entry.key,
            count: entry.value.length,
            mine: myUserId != null &&
                entry.value.any((reaction) => reaction.userId == myUserId),
            palette: palette,
            onTap: () {
              VeilHaptics.selection();
              onChipTap(entry.key);
            },
          ),
      ],
    );
  }
}

class _ReactionChip extends StatelessWidget {
  const _ReactionChip({
    required this.emoji,
    required this.count,
    required this.mine,
    required this.palette,
    required this.onTap,
  });

  final String emoji;
  final int count;
  final bool mine;
  final VeilPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final background = mine ? palette.primarySoft : palette.surfaceAlt;
    final textColor = mine ? palette.primaryStrong : palette.textMuted;
    final countStyle = Theme.of(context).textTheme.labelMedium?.copyWith(color: textColor);
    return Semantics(
      button: true,
      selected: mine,
      label: AppLocalizations.of(context).chatReactionSemantics(emoji, count),
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          // The tap takes 44 px whatever the chip draws.
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            child: Center(
              widthFactor: 1,
              heightFactor: 1,
              child: Container(
                height: 28,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                padding: const EdgeInsets.symmetric(horizontal: VeilSpace.xs),
                decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(14)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(emoji, style: const TextStyle(fontSize: 14, height: 1.2)),
                    const SizedBox(width: VeilSpace.xxs),
                    Text('$count', style: countStyle),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
