import 'dart:math' as math;

import 'package:flutter/material.dart';

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

/// What a long press on a message offers, over the chat where the message
/// is ([anchor], its row on screen): the quick reactions in a floating bar
/// above it and a small menu under it, as WhatsApp and the web app place
/// them, with Save for a photo or file ([onSave]) above Report for a
/// message someone else wrote ([onReport]).
/// Without [onSelected] (a message that did not open, or a 1:1 with someone
/// blocked, where the server refuses a reaction) only the menu shows: under
/// the message, or above it when there is no room under it inside
/// [messages] (the message list on screen; what is under the list, such as
/// a blocked chat's "You blocked @sam." line, stays visible). Everything but
/// the pressed message dims, so the menu reads as its own. A tap outside
/// closes both.
Future<void> showMessageActions(
  BuildContext context, {
  required Rect anchor,
  required bool isMine,
  ValueChanged<String>? onSelected,
  VoidCallback? onReport,
  VoidCallback? onSave,
  Rect? messages,
}) async {
  final l10n = AppLocalizations.of(context);
  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    // The dim is drawn by the page, around the message (MessageActionsDim).
    barrierColor: Colors.transparent,
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
      final rows = [
        if (onSave != null) (const ValueKey('message-save'), l10n.chatSaveAction, onSave),
        if (onReport != null) (const ValueKey('message-report'), l10n.reportAction, onReport),
      ];
      final menu = rows.isEmpty
          ? null
          : DecoratedBox(
              decoration: decoration.copyWith(borderRadius: BorderRadius.circular(VeilRadius.md)),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(VeilRadius.md),
                child: Material(
                  type: MaterialType.transparency,
                  child: SizedBox(
                    width: 200,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final (key, title, action) in rows)
                          VeilRow(
                            key: key,
                            title: title,
                            trailing: const SizedBox.shrink(),
                            onTap: () {
                              Navigator.of(dialogContext).pop();
                              action();
                            },
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            );
      return Stack(fit: StackFit.expand, children: [
        IgnorePointer(
          child: CustomPaint(
            key: const ValueKey('message-actions-dim'),
            painter: MessageActionsDim(anchor, color: light ? MessageActionsDim.lightColor : MessageActionsDim.darkColor),
          ),
        ),
        _MessageActionsLayout(anchor: anchor, isMine: isMine, bar: bar, menu: menu, messages: messages),
      ]);
    },
  );
}

/// The dim behind a message's actions: black over the chat ([color]), except
/// over a band the screen's width at the pressed message's row ([clear]),
/// which stays as it is.
class MessageActionsDim extends CustomPainter {
  const MessageActionsDim(this.clear, {required this.color});

  final Rect clear;
  final Color color;

  /// 20% black in light, over the white chat and its grey bubbles.
  static const Color lightColor = Color(0x33000000);

  /// 50% black in dark: on the black page and the dark grey bubbles 20%
  /// barely shows, and the pressed row would not stand out (WhatsApp's
  /// dark long press dims about as much).
  static const Color darkColor = Color(0x80000000);

  @override
  void paint(Canvas canvas, Size size) {
    final around = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRect(Rect.fromLTRB(0, clear.top, size.width, clear.bottom));
    canvas.drawPath(around, Paint()..color = color);
  }

  @override
  bool shouldRepaint(MessageActionsDim oldDelegate) => oldDelegate.clear != clear || oldDelegate.color != color;
}

/// Places the reaction bar above [anchor] and the menu under it, on the
/// message's side, inside the safe area, by their laid-out heights (taller
/// with larger text). The menu stays next to its message: with no room
/// under it (the newest message), the menu sits right above the message
/// and the bar above the menu; with no room above, both go under it, the
/// bar first.
class _MessageActionsLayout extends StatelessWidget {
  const _MessageActionsLayout({
    required this.anchor,
    required this.isMine,
    this.bar,
    this.menu,
    this.messages,
  });

  final Rect anchor;
  final bool isMine;
  final Widget? bar;
  final Widget? menu;
  final Rect? messages;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final top = media.padding.top + _ActionsPlacement.gap;
    final bottom = media.size.height - media.viewInsets.bottom - media.padding.bottom - _ActionsPlacement.gap;
    return CustomMultiChildLayout(
      delegate: _ActionsPlacement(
        anchor: anchor,
        isMine: isMine,
        top: top,
        bottom: bottom,
        menuAloneBottom: messages == null ? bottom : math.min(bottom, messages!.bottom),
      ),
      children: [
        if (bar != null) LayoutId(id: _ActionsSlot.bar, child: bar!),
        if (menu != null) LayoutId(id: _ActionsSlot.menu, child: menu!),
      ],
    );
  }
}

enum _ActionsSlot { bar, menu }

class _ActionsPlacement extends MultiChildLayoutDelegate {
  _ActionsPlacement({
    required this.anchor,
    required this.isMine,
    required this.top,
    required this.bottom,
    required this.menuAloneBottom,
  });

  static const double gap = VeilSpace.xs;

  final Rect anchor;
  final bool isMine;
  final double top;
  final double bottom;

  /// How low a menu shown without the bar may reach: the message list's
  /// bottom, so what is under the list (a blocked chat's line) stays seen.
  final double menuAloneBottom;

  @override
  void performLayout(Size size) {
    final loose = BoxConstraints.loose(size);
    final barSize = hasChild(_ActionsSlot.bar) ? layoutChild(_ActionsSlot.bar, loose) : null;
    final menuSize = hasChild(_ActionsSlot.menu) ? layoutChild(_ActionsSlot.menu, loose) : null;
    // On the message's side of the message's own column (in the wide layout
    // the chat is a pane, not the screen).
    double x(Size child) => isMine ? anchor.right - VeilSpace.xs - child.width : anchor.left + VeilSpace.xs;
    if (barSize == null) {
      if (menuSize != null) positionChild(_ActionsSlot.menu, Offset(x(menuSize), _menuAloneTop(menuSize.height)));
      return;
    }
    final bar = barSize.height;
    final menu = menuSize == null ? 0.0 : menuSize.height;
    final menuSpan = menuSize == null ? 0.0 : menu + gap;
    final above = anchor.top - gap - top;
    final under = bottom - anchor.bottom - gap;
    final double barTop;
    final double menuTop;
    if (above >= bar && under >= menu) {
      barTop = anchor.top - gap - bar;
      menuTop = anchor.bottom + gap;
    } else if (above >= bar + menuSpan) {
      // Bar, menu, message.
      menuTop = anchor.top - gap - menu;
      barTop = menuTop - gap - bar;
    } else if (under >= bar + menuSpan) {
      // Message, bar, menu.
      barTop = anchor.bottom + gap;
      menuTop = barTop + bar + gap;
    } else {
      // A message taller than the room around it: over its edge, on screen.
      barTop = (anchor.top - gap - bar).clamp(top, math.max(top, bottom - bar));
      menuTop = (barTop + bar + gap).clamp(top, math.max(top, bottom - menu));
    }
    positionChild(_ActionsSlot.bar, Offset(x(barSize), barTop));
    if (menuSize != null) positionChild(_ActionsSlot.menu, Offset(x(menuSize), menuTop));
  }

  // A menu alone: under the message when it fits, else above it.
  double _menuAloneTop(double height) {
    final limit = math.max(top, menuAloneBottom - height);
    if (anchor.bottom + height <= menuAloneBottom) return anchor.bottom.clamp(top, limit);
    final above = anchor.top - gap - height;
    return above >= top ? above : anchor.bottom.clamp(top, limit);
  }

  @override
  bool shouldRelayout(_ActionsPlacement oldDelegate) =>
      anchor != oldDelegate.anchor ||
      isMine != oldDelegate.isMine ||
      top != oldDelegate.top ||
      bottom != oldDelegate.bottom ||
      menuAloneBottom != oldDelegate.menuAloneBottom;
}
