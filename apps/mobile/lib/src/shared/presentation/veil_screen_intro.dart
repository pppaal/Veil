import 'package:flutter/material.dart';

import '../../core/theme/veil_theme.dart';
import 'veil_ui.dart';

/// The opening words of a screen in the previous pass. Screens now open
/// with their control under the bar; wave 1 removes each use. Until then it
/// draws the title and the body as plain text, with no eyebrow.
@Deprecated('W1 migrates; deleted in W0-TOKENS phase 2. Screens open with their control.')
class VeilScreenIntro extends StatelessWidget {
  const VeilScreenIntro({
    super.key,
    required this.title,
    this.eyebrow,
    this.body,
    this.titleStyle,
  });

  /// Ignored: there are no eyebrows.
  final String? eyebrow;
  final String title;
  final String? body;

  /// The headline's style; the theme's medium headline when null.
  final TextStyle? titleStyle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.veilPalette;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: titleStyle ?? theme.textTheme.headlineMedium),
        if (body != null) ...[
          const SizedBox(height: VeilSpace.xs),
          Text(body!, style: theme.textTheme.bodyMedium?.copyWith(color: palette.textMuted)),
        ],
      ],
    );
  }
}
