import 'package:flutter/material.dart';

import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_shell.dart';
import '../../../shared/presentation/veil_ui.dart';
import '../../../shared/presentation/veil_unavailable.dart';
import '../data/emoji_catalog.dart';

/// The emoji picker: a tab per group, and a grid of emoji that has the rest
/// of the screen. Picking one hands it to [onEmojiSelected], or back to the
/// screen that opened the picker as the result of its route.
///
/// It offers emoji only. There are no sticker packs and no GIF search in
/// this build, so it has no tab for either, and no search: emoji carry no
/// names here to search by.
class StickerPickerScreen extends StatelessWidget {
  const StickerPickerScreen({super.key, this.onEmojiSelected});

  /// Takes the picked emoji; the picker then stays open for the next one.
  /// Without it the picker closes with the emoji as its result.
  final ValueChanged<String>? onEmojiSelected;

  /// The widest an emoji cell gets. A row holds as many cells as fit under
  /// it, which keeps every cell above the 44 px a finger needs: 53 px on a
  /// 360 px screen, 50 px on a 390 px one.
  static const double maxCellExtent = 56;

  void _pick(BuildContext context, String emoji) {
    VeilHaptics.selection();
    final onEmojiSelected = this.onEmojiSelected;
    if (onEmojiSelected != null) {
      onEmojiSelected(emoji);
      return;
    }
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop(emoji);
    } else {
      // Opened as the first screen: nobody is waiting for the emoji.
      veilLeaveScreen(context);
    }
  }

  String _label(AppLocalizations l10n, EmojiGroup group) => switch (group) {
        EmojiGroup.smileys => l10n.stickerPickerTabSmileys,
        EmojiGroup.gestures => l10n.stickerPickerTabGestures,
        EmojiGroup.symbols => l10n.stickerPickerTabSymbols,
      };

  @override
  Widget build(BuildContext context) {
    final palette = context.veilPalette;
    final l10n = AppLocalizations.of(context);

    return DefaultTabController(
      length: EmojiGroup.values.length,
      child: VeilShell(
        title: l10n.stickerPickerTitle,
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            TabBar(
              indicatorColor: palette.primary,
              labelColor: palette.text,
              unselectedLabelColor: palette.textSubtle,
              dividerColor: palette.stroke,
              tabs: [for (final group in EmojiGroup.values) Tab(text: _label(l10n, group))],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  for (final group in EmojiGroup.values)
                    GridView.builder(
                      padding: const EdgeInsets.fromLTRB(VeilSpace.lg, VeilSpace.sm, VeilSpace.lg, VeilSpace.xl),
                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: maxCellExtent),
                      itemCount: emojiCatalog[group]!.length,
                      itemBuilder: (context, index) {
                        final emoji = emojiCatalog[group]![index];
                        return _EmojiCell(emoji: emoji, onTap: () => _pick(context, emoji));
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmojiCell extends StatelessWidget {
  const _EmojiCell({required this.emoji, required this.onTap});

  final String emoji;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(VeilRadius.sm),
        onTap: onTap,
        child: Center(
          child: Text(emoji, style: const TextStyle(fontSize: 28)),
        ),
      ),
    );
  }
}
