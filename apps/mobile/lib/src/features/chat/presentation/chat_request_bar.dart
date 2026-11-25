import 'package:flutter/material.dart';

import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_ui.dart';

/// What takes the composer's place in a message request: a chat from an
/// account the user has not talked to, or a group they were added to. It
/// says what waiting means and offers one row of equal buttons: in a 1:1
/// Block (in red), Report and Accept; in a group Leave and Accept. Accept
/// is the filled one unless a warning about the account is up, when it is
/// as plain as the others. Nothing here can be dismissed: the chat stays a
/// request until the user accepts it. It is a panel set off the chat in
/// both themes, whose fill runs on under it through [bottomInset].
class ChatRequestBar extends StatelessWidget {
  const ChatRequestBar({
    super.key,
    required this.body,
    required this.onAccept,
    this.acceptPrimary = true,
    this.onBlock,
    this.onReport,
    this.onLeave,
    this.bottomInset = 0,
  });

  /// The line under the title: what the other side will not know until
  /// the user accepts.
  final String body;
  final VoidCallback onAccept;

  /// Whether Accept is the filled primary button.
  final bool acceptPrimary;

  /// Set in a 1:1.
  final VoidCallback? onBlock;
  final VoidCallback? onReport;

  /// Set in a group.
  final VoidCallback? onLeave;

  /// The screen's bottom inset (the home indicator's strip) under the
  /// composer slot, which the panel's fill covers too, so the panel does
  /// not stop short above a strip of the page's colour.
  final double bottomInset;

  static const double _buttonHeight = 44;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final palette = context.veilPalette;
    final buttonStyle = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(0, _buttonHeight)),
      padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: VeilSpace.xs)),
    );
    Widget plain(String key, String label, VoidCallback onPressed, {bool danger = false}) => TextButton(
          key: ValueKey(key),
          style: danger ? buttonStyle.merge(TextButton.styleFrom(foregroundColor: palette.danger)) : buttonStyle,
          onPressed: onPressed,
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        );
    final accept = acceptPrimary
        ? FilledButton(
            key: const ValueKey('request-accept'),
            style: buttonStyle,
            onPressed: onAccept,
            child: Text(l10n.chatRequestAccept, maxLines: 1, overflow: TextOverflow.ellipsis),
          )
        : plain('request-accept', l10n.chatRequestAccept, onAccept);
    final buttons = [
      if (onBlock case final onBlock?) plain('request-block', l10n.blockAction, onBlock, danger: true),
      if (onReport case final onReport?) plain('request-report', l10n.reportAction, onReport),
      if (onLeave case final onLeave?) plain('request-leave', l10n.chatRequestLeave, onLeave),
      accept,
    ];
    // The light theme's surface is its page, so there the panel takes the
    // grouped pages' grey.
    final fill = theme.brightness == Brightness.light ? palette.canvasAlt : palette.surface;
    return CustomPaint(
      painter: _PanelFill(fill, below: bottomInset),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(VeilSpace.md, VeilSpace.sm, VeilSpace.md, VeilSpace.sm),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.chatRequestTitle, style: theme.textTheme.titleSmall),
            const SizedBox(height: VeilSpace.xxs),
            Text(
              body,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(color: palette.textMuted),
            ),
            const SizedBox(height: VeilSpace.sm),
            Row(
              children: [
                for (final (index, button) in buttons.indexed) ...[
                  if (index > 0) const SizedBox(width: VeilSpace.xs),
                  Expanded(child: SizedBox(height: _buttonHeight, child: button)),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// The panel's fill, carried [below] its bottom edge into the inset.
class _PanelFill extends CustomPainter {
  const _PanelFill(this.color, {required this.below});

  final Color color;
  final double below;

  @override
  void paint(Canvas canvas, Size size) =>
      canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height + below), Paint()..color = color);

  @override
  bool shouldRepaint(_PanelFill old) => old.color != color || old.below != below;
}
