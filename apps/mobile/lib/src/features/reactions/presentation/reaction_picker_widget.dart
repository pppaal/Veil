import 'package:flutter/material.dart';

import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_ui.dart';

/// The quick reactions in a row of 44 px buttons, drawn on the sheet that
/// holds it. The "more" button appears only where
/// [onExpandPressed] gives it something to open: with it the row is wider
/// than a 360 px screen, so it scrolls sideways rather than overflow.
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

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: VeilSpace.xs),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final emoji in _quickReactions)
              _ReactionButton(
                emoji: emoji,
                onTap: () {
                  VeilHaptics.selection();
                  onReactionSelected(emoji);
                },
              ),
            if (onExpandPressed != null) ...[
              Container(
                width: 0.5,
                height: 24,
                margin: const EdgeInsets.symmetric(horizontal: VeilSpace.xs),
                color: palette.strokeStrong,
              ),
              IconButton(
                icon: Icon(Icons.add, size: VeilIconSize.md, color: palette.textMuted),
                tooltip: AppLocalizations.of(context).reactionsMoreTooltip,
                onPressed: () {
                  VeilHaptics.selection();
                  onExpandPressed!();
                },
              ),
            ],
          ],
        ),
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
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(
            child: Text(
              emoji,
              style: const TextStyle(fontSize: 24),
            ),
          ),
        ),
      ),
    );
  }
}
