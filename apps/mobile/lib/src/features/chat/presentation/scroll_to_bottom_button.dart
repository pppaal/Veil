import 'package:flutter/material.dart';

import '../../../core/crypto/crypto_engine.dart';
import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_ui.dart';
import '../../conversations/data/conversation_models.dart';
import '../../conversations/presentation/conversation_row.dart';

/// The round "Scroll to bottom" button of a chat, as Signal and WhatsApp
/// draw it: a 40dp circle at the end edge just above the composer, shown
/// while the newest message is more than a screen below. Its badge counts
/// the messages of others that arrived while the list was away from the
/// bottom, and goes when the list is back there. It is the one control
/// that floats in a chat (design system, section 16).
///
/// Placed by the message list in a Stack over its messages.
class ScrollToBottomButton extends StatefulWidget {
  const ScrollToBottomButton({super.key, required this.scrollController, required this.messages});

  final ScrollController scrollController;

  /// The messages the list shows, oldest first.
  final List<ChatMessage> messages;

  /// The space between the circle and the composer, and the end edge.
  static const double margin = VeilSpace.sm;

  static const double size = 40;

  @override
  State<ScrollToBottomButton> createState() => _ScrollToBottomButtonState();
}

class _ScrollToBottomButtonState extends State<ScrollToBottomButton> {
  bool _shown = false;
  int _arrived = 0;
  String? _newestId;

  // A list this close to its end counts as at the bottom.
  static const double _atBottom = 24;

  @override
  void initState() {
    super.initState();
    _newestId = widget.messages.lastOrNull?.id;
    widget.scrollController.addListener(_scrolled);
    // A list put back where it was (its page storage) moves without telling.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scrolled();
    });
  }

  @override
  void didUpdateWidget(covariant ScrollToBottomButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrollController != widget.scrollController) {
      oldWidget.scrollController.removeListener(_scrolled);
      widget.scrollController.addListener(_scrolled);
    }
    final messages = widget.messages;
    final previous = _newestId;
    _newestId = messages.lastOrNull?.id;
    if (previous == null || previous == _newestId || !_away) return;
    final start = messages.lastIndexWhere((message) => message.id == previous);
    if (start < 0) return;
    _arrived += messages.skip(start + 1).where(_counts).length;
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_scrolled);
    super.dispose();
  }

  // The list's one position: while the chat switches conversations, the
  // controller holds the old list's and the new one's for a frame.
  ScrollPosition? get _position {
    final positions = widget.scrollController.positions;
    return positions.length == 1 ? positions.single : null;
  }

  bool get _away => (_position?.pixels ?? 0) > _atBottom;

  static bool _counts(ChatMessage message) =>
      !message.isMine &&
      !message.isLocalNotice &&
      message.envelope.messageKind != MessageKind.reaction &&
      message.envelope.messageKind != MessageKind.system;

  void _scrolled() {
    final position = _position;
    if (position == null || !position.hasPixels || !position.hasViewportDimension) return;
    final shown = position.pixels > position.viewportDimension;
    final arrived = _away ? _arrived : 0;
    if (shown == _shown && arrived == _arrived) return;
    setState(() {
      _shown = shown;
      _arrived = arrived;
    });
  }

  void _scrollToBottom() {
    final position = _position;
    if (position == null) return;
    VeilHaptics.selection();
    position.animateTo(0, duration: VeilMotion.normal, curve: VeilMotion.smooth);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.veilPalette;
    final arrived = _arrived;
    final button = Semantics(
      button: true,
      label: [l10n.chatScrollToBottom, if (arrived > 0) l10n.chatNewBelowSemantics(arrived)].join(', '),
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _scrollToBottom,
        child: SizedBox.square(
          dimension: 44,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Container(
                width: ScrollToBottomButton.size,
                height: ScrollToBottomButton.size,
                decoration: BoxDecoration(
                  color: palette.surfaceRaised,
                  shape: BoxShape.circle,
                  border: Border.all(color: palette.stroke, width: 0.5),
                ),
                child: Icon(Icons.keyboard_arrow_down, size: 24, color: palette.textMuted),
              ),
              if (arrived > 0)
                Positioned(
                  top: -VeilSpace.xs,
                  child: UnreadBadge(count: arrived),
                ),
            ],
          ),
        ),
      ),
    );
    // The 44 square around the circle reaches 2 past it on each side.
    const inset = ScrollToBottomButton.margin - (44 - ScrollToBottomButton.size) / 2;
    return PositionedDirectional(
      end: inset,
      bottom: inset,
      child: AnimatedSwitcher(
        duration: VeilMotion.fast,
        child: _shown ? button : const SizedBox.shrink(),
      ),
    );
  }
}
