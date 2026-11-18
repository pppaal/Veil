import 'dart:async';
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
/// read under it. The band grows with larger text.
class ChatUnreadDivider extends StatelessWidget {
  const ChatUnreadDivider({super.key, required this.divider, this.bleed = 0, this.afterDay = false});

  /// Its row's id among the chat's message keys, which ChatOpeningPosition
  /// measures it by. No relay message id has a ":".
  static const String rowId = 'unread:divider';

  final UnreadDivider divider;

  /// Right under a day's date, whose space below it is enough.
  final bool afterDay;

  /// How far the band reaches past each side of the list's content, to run
  /// edge to edge across the padding the messages keep (and past the
  /// chat's column, in a pane or screen wider than it).
  final double bleed;

  /// The band's height at the usual text size, the least it takes.
  static const double bandHeight = 28;

  /// The height the divider takes above its message at the usual text size
  /// (ChatOpeningPosition measures the one laid out).
  static const double extent = bandHeight + 2 * VeilSpace.md;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.veilPalette;
    final text = divider.olderThanLoaded ? l10n.chatUnreadDividerNoCount : l10n.chatUnreadDivider(divider.count);
    return Padding(
      padding: EdgeInsets.only(top: afterDay ? 0 : VeilSpace.md, bottom: VeilSpace.md),
      child: LayoutBuilder(
        // As tall as the band, as wide as the list's content: the band
        // reaches past it on both sides.
        builder: (context, constraints) => OverflowBox(
          fit: OverflowBoxFit.deferToChild,
          minWidth: constraints.maxWidth + 2 * bleed,
          maxWidth: constraints.maxWidth + 2 * bleed,
          child: Container(
            constraints: const BoxConstraints(minHeight: bandHeight),
            color: palette.surfaceAlt,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: VeilSpace.md, vertical: VeilSpace.xxs),
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: palette.textMuted),
            ),
          ),
        ),
      ),
    );
  }
}

/// Clips the message area above and below only, so the unread band can run
/// [sideRoom] past each side of it: out to the edges of a pane or screen
/// wider than the chat's column.
class ChatUnreadBandClip extends CustomClipper<Rect> {
  const ChatUnreadBandClip(this.sideRoom);

  final double sideRoom;

  @override
  Rect getClip(Size size) => Rect.fromLTRB(-sideRoom, 0, size.width + sideRoom, size.height);

  @override
  bool shouldReclip(ChatUnreadBandClip oldClipper) => oldClipper.sideRoom != sideRoom;
}

/// Opens a chat where its unread messages start, once per [divider]: at
/// the bottom as always when the unread run fits on the screen, or else
/// with the divider about a third down, so the first unread message and
/// what follows it are what the user sees first, with a line of what came
/// before above it.
///
/// The list runs upwards from the composer and builds only the rows near
/// the screen, so the first unread row may not exist yet: the list moves a
/// screenful at a time towards it until it does. A photo or a file row is
/// a small placeholder until its content is in, and grows then: until the
/// user scrolls, or [followFor] has passed, the place is checked again
/// whenever the list's extent changes, so a run that grows past the screen
/// still opens at its divider.
class ChatOpeningPosition extends StatefulWidget {
  const ChatOpeningPosition({
    super.key,
    required this.divider,
    required this.scrollController,
    required this.rowContextOf,
    required this.child,
  });

  /// How long the place follows rows that grow, unless the user scrolls.
  static const Duration followFor = Duration(seconds: 2);

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
  // Whether the list left the bottom for the divider (or on its way to it).
  bool _moved = false;
  // Which placement runs; an older one stops at its next step.
  int _run = 0;
  // While it runs, a change of the list's extent places the divider again.
  Timer? _following;
  bool _jumping = false;
  bool _recheckScheduled = false;

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

  @override
  void dispose() {
    _following?.cancel();
    super.dispose();
  }

  void _placeOnce() {
    final divider = widget.divider;
    if (divider == null || identical(divider, _placed)) return;
    _placed = divider;
    _moved = false;
    _following?.cancel();
    _following = Timer(ChatOpeningPosition.followFor, () => _following = null);
    _place(divider);
  }

  // Steps once a frame until the divider is in its place; it stops when the
  // user scrolls, when the window to follow closes, or when another run
  // takes over.
  Future<void> _place(UnreadDivider divider) async {
    final run = ++_run;
    for (var step = 0; step < 40; step++) {
      WidgetsBinding.instance.scheduleFrame();
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || !identical(divider, _placed) || run != _run || _following == null) return;
      if (_step(divider)) return;
    }
  }

  // One move towards the divider's place; true once it is there, or the
  // run fits and the list stays at the bottom.
  bool _step(UnreadDivider divider) {
    final positions = widget.scrollController.positions;
    // While the chat switches conversations the controller holds two
    // lists' positions for a frame.
    if (positions.length != 1) return false;
    final position = positions.single;
    final row = widget.rowContextOf(divider.firstMessageId)?.findRenderObject();
    if (row is! RenderBox || !row.attached) {
      // Older rows lie further along the list.
      final next = math.min(position.pixels + position.viewportDimension, position.maxScrollExtent);
      if (next <= position.pixels) return true;
      _jump(position, next);
      return false;
    }
    // At [reveal] the row's top meets the top of the list; a larger
    // offset brings it further down the screen. The divider above it is
    // as tall as it was laid out (taller with larger text).
    final reveal = RenderAbstractViewport.of(row).getOffsetToReveal(row, 1).offset;
    final band = widget.rowContextOf(ChatUnreadDivider.rowId)?.findRenderObject();
    final extent = band is RenderBox && band.attached && band.hasSize ? band.size.height : ChatUnreadDivider.extent;
    final viewport = position.viewportDimension;
    if (!_moved && position.pixels - reveal - extent >= 0) return true;
    final target = (reveal + extent + viewport / 3)
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    // The list learns how long it is as it builds: once more until it
    // stays put.
    if ((target - position.pixels).abs() < 1) return true;
    _jump(position, target);
    return false;
  }

  void _jump(ScrollPosition position, double offset) {
    _jumping = true;
    try {
      position.jumpTo(offset);
    } finally {
      _jumping = false;
    }
    _moved = true;
  }

  bool _onNotification(Notification notification) {
    final divider = _placed;
    if (_following == null || divider == null) return false;
    if (notification is ScrollStartNotification && notification.depth == 0 && !_jumping) {
      // The user (or the button to the newest message) moves the list:
      // from now on it stays where they take it.
      _following?.cancel();
      _following = null;
    } else if (notification is ScrollMetricsNotification && notification.depth == 0 && !_recheckScheduled) {
      _recheckScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _recheckScheduled = false;
        if (mounted && _following != null && identical(divider, _placed)) _place(divider);
      });
    }
    return false;
  }

  @override
  Widget build(BuildContext context) =>
      NotificationListener<Notification>(onNotification: _onNotification, child: widget.child);
}
