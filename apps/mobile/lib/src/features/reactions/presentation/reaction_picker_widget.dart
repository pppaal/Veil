import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/veil_theme.dart';
import '../../../shared/presentation/veil_ui.dart';

class ReactionPickerWidget extends StatelessWidget {
  const ReactionPickerWidget({
    super.key,
    required this.onReactionSelected,
    this.onExpandPressed,
  });

  final ValueChanged<String> onReactionSelected;
  final VoidCallback? onExpandPressed;

  static const _quickReactions = [
    '\u{1F44D}', // 👍
    '\u{2764}\u{FE0F}', // ❤️
    '\u{1F602}', // 😂
    '\u{1F62E}', // 😮
    '\u{1F622}', // 😢
    '\u{1F525}', // 🔥
  ];

  @override
  Widget build(BuildContext context) {
    final palette = context.veilPalette;

    return VeilSurfaceCard(
      padding: const EdgeInsets.symmetric(
        horizontal: VeilSpace.sm,
        vertical: VeilSpace.xs,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final emoji in _quickReactions)
            _ReactionButton(
              emoji: emoji,
              onTap: () {
                HapticFeedback.selectionClick();
                onReactionSelected(emoji);
              },
            ),
          Container(
            width: 1,
            height: 24,
            margin: const EdgeInsets.symmetric(horizontal: VeilSpace.xs),
            color: palette.stroke,
          ),
          SizedBox(
            width: 36,
            height: 36,
            child: IconButton(
              padding: EdgeInsets.zero,
              icon: Icon(
                Icons.add_rounded,
                size: VeilIconSize.sm,
                color: palette.textMuted,
              ),
              tooltip: 'More reactions',
              onPressed: () {
                HapticFeedback.selectionClick();
                onExpandPressed?.call();
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ReactionButton extends StatelessWidget {
  const _ReactionButton({
    required this.emoji,
    required this.onTap,
  });

  final String emoji;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(VeilRadius.sm),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(VeilSpace.xs),
          child: Text(
            emoji,
            style: const TextStyle(fontSize: 22),
          ),
        ),
      ),
    );
  }
}
