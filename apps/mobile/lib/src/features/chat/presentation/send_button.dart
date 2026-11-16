import 'package:flutter/material.dart';

import '../../../core/theme/veil_theme.dart';
import '../../../shared/presentation/veil_ui.dart';

/// The composer's send button: a 32dp brand circle with an up arrow, inside
/// a 44x44 tap target. It is there only while there is a draft to send:
/// without [onPressed] it takes no room, and the field has the whole width
/// until the first character slides the button in (iMessage).
class SendButton extends StatelessWidget {
  const SendButton({super.key, required this.onPressed, required this.semanticLabel});

  /// Sends the draft; null when there is nothing to send.
  final VoidCallback? onPressed;

  /// What a screen reader calls the button.
  final String semanticLabel;

  /// The side of the tap target.
  static const double extent = 44;

  /// The diameter of the circle drawn in it.
  static const double diameter = 32;

  @override
  Widget build(BuildContext context) {
    final onPressed = this.onPressed;
    if (onPressed == null) return const SizedBox.shrink();
    final palette = context.veilPalette;
    return Semantics(
      button: true,
      label: semanticLabel,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          VeilHaptics.light();
          onPressed();
        },
        child: SizedBox(
          width: extent,
          height: extent,
          child: Center(
            child: DecoratedBox(
              decoration: BoxDecoration(shape: BoxShape.circle, color: palette.primary),
              child: const SizedBox(
                width: diameter,
                height: diameter,
                child: Icon(Icons.arrow_upward, size: VeilIconSize.sm, color: Colors.white),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
