import 'package:flutter/material.dart';

import '../../core/theme/veil_theme.dart';
import 'veil_ui.dart';

/// Something the user has to decide or do: a safety number that changed,
/// messages that were not sent, a device gone stale. Information is plain
/// text, never a notice.
///
/// A grey box (`surfaceAlt`, rounded by 10) with a 20dp icon in the tone
/// colour, a title, a line of body and at most one text button at the end.
/// On a white page it keeps 12dp from the sides ([margin]); inside a
/// [VeilGroup] it is a row, with no margin and no corners. [dense] is one
/// 44dp row, for a chat with no height to spare: the icon, one line with an
/// ellipsis and the button. Where the height is there, [denseLines] lets
/// that line wrap instead of losing its end.
class VeilNotice extends StatelessWidget {
  const VeilNotice({
    super.key,
    required this.message,
    this.title,
    this.tone = VeilTone.info,
    this.icon,
    this.dense = false,
    this.denseLines = 1,
    this.actionLabel,
    this.onAction,
    this.margin,
  });

  final String? title;
  final String message;
  final VeilTone tone;

  /// Replaces the tone's own icon.
  final IconData? icon;
  final bool dense;

  /// How many lines the text of a [dense] notice may take before it ends
  /// in an ellipsis.
  final int denseLines;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// The space around the box on a white page; 12 at the sides when null.
  final EdgeInsetsGeometry? margin;

  /// The height of a dense notice whose text fits one line.
  static const double denseHeight = 44;

  static IconData iconFor(VeilTone tone) => switch (tone) {
        VeilTone.info => Icons.info_outlined,
        VeilTone.good => Icons.check_circle_outline,
        VeilTone.warn => Icons.warning_amber_outlined,
        VeilTone.danger => Icons.error_outline,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.veilPalette;
    final inGroup = VeilGroup.isInside(context);
    final toneColor = veilToneColor(palette, tone);
    final actionColor = tone == VeilTone.danger ? palette.danger : palette.primaryStrong;
    final hasAction = actionLabel != null;
    final glyph = Icon(icon ?? iconFor(tone), size: 20, color: toneColor);
    // An empty title (an ARB value emptied before its screen stops passing
    // it) is no title: the body takes the first line.
    final title = (this.title?.isEmpty ?? true) ? null : this.title;

    final Widget content;
    if (dense) {
      final line = title ?? message;
      content = ConstrainedBox(
        constraints: const BoxConstraints(minHeight: denseHeight),
        child: Row(
          children: [
            glyph,
            const SizedBox(width: VeilSpace.xs),
            Expanded(
              child: Text(
                line,
                semanticsLabel: title == null ? message : '$title  $message',
                maxLines: denseLines,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall,
              ),
            ),
            if (hasAction)
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: actionColor,
                  minimumSize: const Size(denseHeight, denseHeight),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: onAction,
                child: Text(actionLabel!),
              ),
          ],
        ),
      );
    } else {
      content = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(padding: const EdgeInsets.only(top: 1), child: glyph),
          const SizedBox(width: VeilSpace.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null) ...[
                  Text(title, style: theme.textTheme.titleSmall),
                  const SizedBox(height: 2),
                ],
                Text(message, style: theme.textTheme.bodyMedium?.copyWith(color: palette.textMuted)),
                if (hasAction)
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    // 44 tall with no padded tap area under it: the button
                    // ends the box, its label about as far from the bottom
                    // as the icon is from the top.
                    child: TextButton(
                      style: TextButton.styleFrom(
                        foregroundColor: actionColor,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: onAction,
                      child: Text(actionLabel!),
                    ),
                  ),
              ],
            ),
          ),
        ],
      );
    }

    final box = Container(
      padding: dense
          ? EdgeInsets.only(left: VeilSpace.sm, right: hasAction ? VeilSpace.xxs : VeilSpace.sm)
          : EdgeInsets.fromLTRB(VeilSpace.sm, VeilSpace.sm, VeilSpace.sm, hasAction ? 0 : VeilSpace.sm),
      decoration: BoxDecoration(
        color: palette.surfaceAlt,
        borderRadius: inGroup ? null : BorderRadius.circular(VeilRadius.md),
      ),
      child: content,
    );
    if (inGroup) return box;
    return Padding(padding: margin ?? const EdgeInsets.symmetric(horizontal: VeilSpace.sm), child: box);
  }
}
