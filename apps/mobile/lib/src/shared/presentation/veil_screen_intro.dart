import 'package:flutter/material.dart';

import '../../core/theme/veil_theme.dart';
import 'veil_ui.dart';

/// The opening words of a screen: a small label over the one line the
/// screen is about, and a sentence under it. It says what a hero panel
/// says without the panel around it, so that the field or button the
/// screen is for stays on the first screenful of a phone.
///
/// [title] and [body] are the app's own copy: their Korean words stay whole
/// where a line wraps. [trailing] sits at the end of the title's row (a
/// status pill, say) and keeps its own width.
class VeilScreenIntro extends StatelessWidget {
  const VeilScreenIntro({
    super.key,
    required this.title,
    this.eyebrow,
    this.body,
    this.trailing,
    this.titleStyle,
  });

  final String? eyebrow;
  final String title;
  final String? body;
  final Widget? trailing;

  /// The headline's style; the theme's small headline when null.
  final TextStyle? titleStyle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.veilPalette;
    final headline = VeilCopy(title, style: titleStyle ?? theme.textTheme.headlineSmall);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (eyebrow != null) ...[
          Text(eyebrow!, style: theme.textTheme.labelLarge?.copyWith(color: palette.primaryStrong)),
          const SizedBox(height: VeilSpace.xs),
        ],
        if (trailing == null)
          headline
        else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: headline),
              const SizedBox(width: VeilSpace.sm),
              trailing!,
            ],
          ),
        if (body != null) ...[
          const SizedBox(height: VeilSpace.xs),
          VeilCopy(body!, style: theme.textTheme.bodyMedium?.copyWith(color: palette.textMuted)),
        ],
      ],
    );
  }
}
