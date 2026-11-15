import 'package:flutter/material.dart';

import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_ui.dart';

/// Someone is typing: a small incoming bubble with three muted dots, on the
/// side the peer's messages are on, and who it is beside it; nothing when
/// no one is. A 1:1 only says that they are typing; a group ([named]) says
/// who.
class TypingIndicator extends StatelessWidget {
  const TypingIndicator({super.key, required this.handle, this.named = true});

  /// The handle of who is typing, or null when no one is.
  final String? handle;

  /// Whether to name them: in a group, where it could be anyone.
  final bool named;

  @override
  Widget build(BuildContext context) {
    if (handle == null || handle!.isEmpty) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context);
    final palette = context.veilPalette;
    return Padding(
      // In line with the peer's bubbles above it.
      padding: const EdgeInsets.fromLTRB(VeilSpace.sm, VeilSpace.xxs, VeilSpace.md, VeilSpace.xxs),
      child: Row(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: palette.surfaceAlt,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(VeilRadius.xl),
                topRight: const Radius.circular(VeilRadius.xl),
                bottomRight: const Radius.circular(VeilRadius.xl),
                bottomLeft: Radius.circular(VeilBubble.tailRadius(VeilBubblePosition.single)),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: VeilSpace.sm, vertical: VeilSpace.sm),
              child: _TypingDots(color: palette.textMuted),
            ),
          ),
          const SizedBox(width: VeilSpace.xs),
          Flexible(
            child: Text(
              named ? l10n.chatTypingSuffix(handle!) : l10n.chatTypingUnnamed,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: palette.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}

/// Three 6dp dots whose opacity runs along them, one after the other.
class _TypingDots extends StatefulWidget {
  const _TypingDots({required this.color});

  final Color color;

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final t = (_controller.value - i * 0.2) % 1.0;
            final opacity = (t < 0.5 ? t : 1.0 - t) * 1.2 + 0.4;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: opacity.clamp(0.0, 1.0)),
                  shape: BoxShape.circle,
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
