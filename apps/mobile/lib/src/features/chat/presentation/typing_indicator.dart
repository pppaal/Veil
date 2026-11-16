import 'package:flutter/material.dart';

import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_ui.dart';

/// Someone is typing: a small incoming bubble with three muted dots, on the
/// side the peer's messages are on; nothing when no one is. In a 1:1 the
/// dots are all (a screen reader hears that they are typing); a group
/// ([name]) says beside them who it is.
class TypingIndicator extends StatelessWidget {
  const TypingIndicator({super.key, required this.handle, this.name});

  /// The handle of who is typing, or null when no one is.
  final String? handle;

  /// What to call them beside the dots, in a group, where it could be
  /// anyone (as the group's bubbles call them); null in a 1:1.
  final String? name;

  bool get named => name != null;

  @override
  Widget build(BuildContext context) {
    if (handle == null || handle!.isEmpty) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context);
    final palette = context.veilPalette;
    final label = named ? l10n.chatTypingSuffix(name!) : l10n.chatTypingUnnamed;
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
              child: Semantics(
                label: named ? null : label,
                child: _TypingDots(color: palette.textMuted),
              ),
            ),
          ),
          if (named) ...[
            const SizedBox(width: VeilSpace.xs),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: palette.textMuted),
              ),
            ),
          ],
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
