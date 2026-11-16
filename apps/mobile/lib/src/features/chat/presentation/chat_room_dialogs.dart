import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/security/sensitive_text_redactor.dart';
import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_ui.dart';
import '../../reactions/presentation/reaction_picker_widget.dart';

/// Asks before a 1:1 is bound to another account listed under the user's
/// own handle, which no honest relay lists. True only when confirmed.
Future<bool> confirmOwnHandleHold(BuildContext context, String handle) async {
  final l10n = AppLocalizations.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.chatAccountHoldOwnConfirmTitle(handle)),
      content: Text(l10n.chatAccountHoldOwnConfirmBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.commonCancel),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.chatAccountHoldAcknowledge),
        ),
      ],
    ),
  );
  return confirmed == true;
}

/// Tells the user a download ticket was issued, showing only a redacted
/// summary of its [url], never the URL itself.
Future<void> showAttachmentTicketDialog(BuildContext context, String url) async {
  final ticketSummary = summarizeSensitiveUrl(url);
  final l10n = AppLocalizations.of(context);
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.chatAttachmentTicketTitle),
      content: Text(l10n.chatAttachmentTicketBody(ticketSummary)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonClose),
        ),
      ],
    ),
  );
}

/// What a long press on a message offers, over the chat where the message
/// is ([anchor], its row on screen): the quick reactions in a floating bar
/// above it and, with [onReport] (a message someone else wrote), a small
/// menu under it with Report, as WhatsApp and the web app place them.
/// Without [onSelected] (a message that did not open, or a 1:1 with someone
/// blocked, where the server refuses a reaction) only the menu shows: under
/// the message, or above it when there is no room under it inside
/// [messages] (the message list on screen; what is under the list, such as
/// a blocked chat's "You blocked @sam." line, stays visible). A tap outside
/// closes both.
Future<void> showMessageActions(
  BuildContext context, {
  required Rect anchor,
  required bool isMine,
  ValueChanged<String>? onSelected,
  VoidCallback? onReport,
  Rect? messages,
}) async {
  final l10n = AppLocalizations.of(context);
  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: const Color(0x33000000),
    transitionDuration: VeilMotion.fast,
    pageBuilder: (dialogContext, _, __) {
      final palette = dialogContext.veilPalette;
      final light = Theme.of(dialogContext).brightness == Brightness.light;
      final decoration = BoxDecoration(
        color: palette.surfaceRaised,
        borderRadius: BorderRadius.circular(VeilRadius.xl),
        boxShadow: light ? VeilElevation.modal : null,
      );
      final bar = onSelected == null
          ? null
          : DecoratedBox(
              decoration: decoration,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: VeilSpace.xxs),
                child: ReactionPickerWidget(
                  onReactionSelected: (emoji) {
                    Navigator.of(dialogContext).pop();
                    onSelected(emoji);
                  },
                ),
              ),
            );
      final menu = onReport == null
          ? null
          : DecoratedBox(
              decoration: decoration.copyWith(borderRadius: BorderRadius.circular(VeilRadius.md)),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(VeilRadius.md),
                child: Material(
                  type: MaterialType.transparency,
                  child: SizedBox(
                    width: 200,
                    child: VeilRow(
                      key: const ValueKey('message-report'),
                      title: l10n.reportAction,
                      trailing: const SizedBox.shrink(),
                      onTap: () {
                        Navigator.of(dialogContext).pop();
                        onReport();
                      },
                    ),
                  ),
                ),
              ),
            );
      return _MessageActionsLayout(anchor: anchor, isMine: isMine, bar: bar, menu: menu, messages: messages);
    },
  );
}

/// Places the reaction bar above [anchor] (below it when there is no room)
/// and the menu under it, on the message's side, inside the safe area.
class _MessageActionsLayout extends StatelessWidget {
  const _MessageActionsLayout({required this.anchor, required this.isMine, this.bar, this.menu, this.messages});

  final Rect anchor;
  final bool isMine;
  final Widget? bar;
  final Widget? menu;
  final Rect? messages;

  // A menu alone: under the message when it fits above [bottom], else above
  // the message.
  double _menuAloneTop(double top, double bottom) {
    if (anchor.bottom + _menuHeight <= bottom) return anchor.bottom.clamp(top, bottom - _menuHeight);
    final above = anchor.top - _gap - _menuHeight;
    return above >= top ? above : anchor.bottom.clamp(top, bottom - _menuHeight);
  }

  static const double _barHeight = 52;
  static const double _menuHeight = 52;
  static const double _gap = VeilSpace.xs;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final size = media.size;
    final top = media.padding.top + _gap;
    final bottom = size.height - media.viewInsets.bottom - media.padding.bottom - _gap;
    var barTop = anchor.top - _gap - _barHeight;
    var menuTop = anchor.bottom + _gap;
    if (barTop < top) {
      // No room above: the bar goes under the message, the menu under it.
      barTop = (anchor.bottom + _gap).clamp(top, bottom - _barHeight);
      menuTop = barTop + _barHeight + _gap;
    }
    if (menuTop + _menuHeight > bottom) menuTop = (barTop - _gap - _menuHeight).clamp(top, bottom - _menuHeight);
    // On the message's side of the message's own column (in the wide layout
    // the chat is a pane, not the screen).
    Widget place(double y, Widget child) => Positioned(
          top: y,
          left: isMine ? null : anchor.left + VeilSpace.xs,
          right: isMine ? size.width - anchor.right + VeilSpace.xs : null,
          child: child,
        );
    return Stack(
      children: [
        if (bar != null) place(barTop, bar!),
        if (menu != null)
          place(
            bar == null ? _menuAloneTop(top, messages == null ? bottom : math.min(bottom, messages!.bottom)) : menuTop,
            menu!,
          ),
      ],
    );
  }
}
