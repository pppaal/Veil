import 'package:flutter/material.dart';

import '../../../core/theme/veil_theme.dart';
import '../../../shared/presentation/veil_ui.dart';

/// The composer's round send button; disabled (grey) without [onPressed].
class GradientSendButton extends StatelessWidget {
  const GradientSendButton({super.key, this.onPressed, this.busy = false});

  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final palette = context.veilPalette;
    final enabled = onPressed != null;
    return GestureDetector(
      onTap: enabled
          ? () {
              VeilHaptics.light();
              onPressed!();
            }
          : null,
      child: AnimatedContainer(
        duration: VeilMotion.fast,
        curve: VeilMotion.springGentle,
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: enabled
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [palette.primary, palette.accent],
                )
              : null,
          color: enabled ? null : palette.surfaceOverlay,
          boxShadow: enabled
              ? [
                  BoxShadow(
                    color: palette.primary.withValues(alpha: 0.32),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Icon(
          busy ? Icons.more_horiz_rounded : Icons.arrow_upward_rounded,
          color: enabled ? Colors.white : palette.textSubtle,
          size: 22,
        ),
      ),
    );
  }
}
