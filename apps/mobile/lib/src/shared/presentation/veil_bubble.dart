import 'package:flutter/material.dart';

import '../../core/theme/veil_theme.dart';
import 'veil_ui.dart';

/// Where a bubble sits in a run of bubbles from the same sender.
enum VeilBubblePosition { first, middle, last, single }

/// A message bubble: a solid fill with no border, shadow or gradient, at
/// most 78% of the width it is given. Own bubbles are `primary` with white
/// text; others are `surfaceAlt` in the text colour. The main corners are
/// 18; the corner on the tail side (bottom right for own bubbles, bottom
/// left for others) is 4 at the end of a run and 6 inside one.
///
/// [highlighted] (a search hit) is a `surfaceRaised` fill with a 1.5dp
/// `primaryStrong` border. [failed] is drawn like an incoming bubble, with
/// [failedText] ("Not sent. Tap to retry.") in the danger colour under the
/// content.
class VeilBubble extends StatelessWidget {
  const VeilBubble({
    super.key,
    required this.child,
    required this.isMine,
    this.highlighted = false,
    this.position = VeilBubblePosition.single,
    this.failed = false,
    this.failedText,
  });

  final Widget child;
  final bool isMine;
  final bool highlighted;
  final VeilBubblePosition position;
  final bool failed;
  final String? failedText;

  /// The share of the available width a bubble may take.
  static const double widthShare = 0.78;

  /// The radius of the tail-side bottom corner for [position].
  static double tailRadius(VeilBubblePosition position) => switch (position) {
        VeilBubblePosition.last || VeilBubblePosition.single => 4,
        VeilBubblePosition.first || VeilBubblePosition.middle => 6,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.veilPalette;
    final tail = Radius.circular(tailRadius(position));
    const main = Radius.circular(VeilRadius.xl);
    final own = isMine && !failed && !highlighted;
    final fill = highlighted
        ? palette.surfaceRaised
        : own
            ? palette.primary
            : palette.surfaceAlt;
    final textColor = own ? Colors.white : palette.text;

    return LayoutBuilder(
      builder: (context, constraints) {
        // In a row the width is unbounded; the screen's then stands in.
        final available = constraints.maxWidth.isFinite ? constraints.maxWidth : MediaQuery.sizeOf(context).width;
        final maxWidth = available * widthShare;
        return ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.only(
                topLeft: main,
                topRight: main,
                bottomLeft: isMine ? main : tail,
                bottomRight: isMine ? tail : main,
              ),
              border: highlighted ? Border.all(color: palette.primaryStrong, width: 1.5) : null,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: VeilSpace.sm, vertical: VeilSpace.xs),
              child: DefaultTextStyle.merge(
                style: TextStyle(color: textColor),
                child: IconTheme.merge(
                  data: IconThemeData(color: own ? Colors.white : palette.textMuted),
                  child: failed && failedText != null
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            child,
                            const SizedBox(height: VeilSpace.xxs),
                            Text(failedText!, style: theme.textTheme.bodySmall?.copyWith(color: palette.danger)),
                          ],
                        )
                      : child,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
