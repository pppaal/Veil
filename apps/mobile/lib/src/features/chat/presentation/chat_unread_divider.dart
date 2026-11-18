import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_ui.dart';
import '../../conversations/data/messenger/read_state_service.dart';

/// The line above the first message that was unread when the chat opened,
/// as Signal, Telegram and WhatsApp draw it: "4 unread messages" in small
/// muted type on a full-width band, with the day divider's space around it.
/// "Unread messages" when the first unread one is older than what is
/// loaded. It stays while the chat is on screen, however many messages are
/// read under it.
class ChatUnreadDivider extends StatelessWidget {
  const ChatUnreadDivider({super.key, required this.divider, this.bleed = 0, this.afterDay = false});

  final UnreadDivider divider;

  /// Right under a day's date, whose space below it is enough.
  final bool afterDay;

  /// How far the band reaches past each side of the list's content, to run
  /// edge to edge across the padding the messages keep.
  final double bleed;

  static const double bandHeight = 28;

  /// The height the divider takes above its message.
  static const double extent = bandHeight + 2 * VeilSpace.md;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.veilPalette;
    final text = divider.olderThanLoaded ? l10n.chatUnreadDividerNoCount : l10n.chatUnreadDivider(divider.count);
    return Padding(
      padding: EdgeInsets.only(top: afterDay ? 0 : VeilSpace.md, bottom: VeilSpace.md),
      child: LayoutBuilder(
        builder: (context, constraints) => SizedBox(
          height: bandHeight,
          child: OverflowBox(
            minWidth: constraints.maxWidth + 2 * bleed,
            maxWidth: constraints.maxWidth + 2 * bleed,
            child: Container(
              color: palette.surfaceAlt,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: VeilSpace.md),
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: palette.textMuted),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Opens a chat where its unread messages start, once per [divider]: at
/// the bottom as always when the unread run fits on the screen, or else
/// with the divider about a third down, so the first unread message and
/// what follows it are what the user sees first, with a line of what came
/// before above it.
///
/// The list runs upwards from the composer and builds only the rows near
/// the screen, so the first unread row may not exist yet: the list moves a
/// screenful at a time towards it until it does.
class ChatOpeningPosition extends StatefulWidget {
  const ChatOpeningPosition({
    super.key,
    required this.divider,
    required this.scrollController,
    required this.rowContextOf,
    required this.child,
  });

  final UnreadDivider? divider;
  final ScrollController scrollController;

  /// The built row of a message, if it is built.
  final BuildContext? Function(String messageId) rowContextOf;
  final Widget child;

  @override
  State<ChatOpeningPosition> createState() => _ChatOpeningPositionState();
}

class _ChatOpeningPositionState extends State<ChatOpeningPosition> {
  UnreadDivider? _placed;

  @override
  void initState() {
    super.initState();
    _placeOnce();
  }

  @override
  void didUpdateWidget(covariant ChatOpeningPosition oldWidget) {
    super.didUpdateWidget(oldWidget);
    _placeOnce();
  }

  void _placeOnce() {
    final divider = widget.divider;
    if (divider == null || identical(divider, _placed)) return;
    _placed = divider;
    _place(divider);
  }

  Future<void> _place(UnreadDivider divider) async {
    var moved = false;
    for (var step = 0; step < 40; step++) {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || !identical(divider, _placed)) return;
      final positions = widget.scrollController.positions;
      // While the chat switches conversations the controller holds two
      // lists' positions for a frame.
      if (positions.length != 1) continue;
      final position = positions.single;
      final row = widget.rowContextOf(divider.firstMessageId)?.findRenderObject();
      if (row is! RenderBox || !row.attached) {
        // Older rows lie further along the list.
        final next = math.min(position.pixels + position.viewportDimension, position.maxScrollExtent);
        if (next <= position.pixels) return;
        position.jumpTo(next);
        moved = true;
        continue;
      }
      // At [reveal] the row's top meets the top of the list; a larger
      // offset brings it further down the screen.
      final reveal = RenderAbstractViewport.of(row).getOffsetToReveal(row, 1).offset;
      final viewport = position.viewportDimension;
      if (!moved && position.pixels - reveal - ChatUnreadDivider.extent >= 0) return;
      final target = (reveal + ChatUnreadDivider.extent + viewport / 3)
          .clamp(position.minScrollExtent, position.maxScrollExtent)
          .toDouble();
      // The list learns how long it is as it builds: once more until it
      // stays put.
      if ((target - position.pixels).abs() < 1) return;
      position.jumpTo(target);
      moved = true;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
