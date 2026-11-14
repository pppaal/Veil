import 'package:flutter/material.dart';

import '../../../core/theme/veil_theme.dart';
import '../../../shared/presentation/veil_ui.dart';
import '../../conversations/data/conversation_models.dart';

/// The reactions under a message, one chip per emoji with its count, the
/// most used first. A chip this user added to is highlighted.
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
      spacing: VeilSpace.xs,
      runSpacing: VeilSpace.xs,
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
    final border = mine ? palette.primary : palette.stroke;
    final textColor = mine ? palette.primaryStrong : palette.textMuted;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(VeilRadius.pill),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: VeilSpace.sm,
            vertical: VeilSpace.xs,
          ),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(VeilRadius.pill),
            border: Border.all(color: border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(emoji, style: const TextStyle(fontSize: 14)),
              const SizedBox(width: 4),
              Text(
                '$count',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: textColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
