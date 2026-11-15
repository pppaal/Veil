import 'package:flutter/material.dart';

import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_ui.dart';

/// Three pulsing dots and who is typing, on the side the peer's messages
/// are on, or nothing when no one is. A 1:1 only says that they are typing;
/// a group ([named]) says who.
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
      // In line with the text of the peer's bubbles above it.
      padding: const EdgeInsets.fromLTRB(VeilSpace.sm + VeilSpace.md, VeilSpace.xxs, VeilSpace.md, 0),
      child: Row(
        children: [
          SizedBox(width: 24, height: 12, child: _TypingDots(color: palette.textMuted)),
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

class _TypingDots extends StatefulWidget {
  const _TypingDots({required this.color});

  final Color color;

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
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
            final delay = i * 0.2;
            final t = (_controller.value - delay) % 1.0;
            final scale = (t < 0.5 ? t : 1.0 - t) * 0.6 + 0.7;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1),
              child: Transform.scale(
                scale: scale,
                child: Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
