import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_state.dart';
import '../../../core/theme/veil_theme.dart';
import '../../conversations/data/conversation_models.dart';

/// Brings the message a navigation target names into view: loads up to four
/// pages of older history until it is there, highlights it, scrolls to it,
/// and drops the highlight two seconds later.
///
/// The message list builds only the rows around what is on screen, so the
/// target usually has no row yet. The list is then moved a screenful at a
/// time towards the target until its row is built, and only then scrolled
/// to it.
mixin NavigationTargetJump<W extends ConsumerStatefulWidget> on ConsumerState<W> {
  /// The key each shown message is built under, kept by the message list.
  final Map<String, GlobalKey> messageKeys = <String, GlobalKey>{};
  Timer? _highlightClearTimer;
  String? _highlightedMessageId;
  int _jumpSerial = 0;

  /// The conversation the chat shows.
  String get conversationId;

  /// The message to bring into view, if any.
  MessageNavigationTarget? get navigationTarget;

  /// The controller of the list the messages scroll in.
  ScrollController get messageScrollController;

  /// The ids of the messages the list shows now, oldest first.
  List<String> get shownMessageIds;

  String? get highlightedMessageId => _highlightedMessageId;

  /// Forgets the highlight and the keys, as when the chat switches to
  /// another conversation.
  void resetNavigationTarget() {
    _jumpSerial += 1;
    _highlightedMessageId = null;
    messageKeys.clear();
  }

  @override
  void dispose() {
    _highlightClearTimer?.cancel();
    super.dispose();
  }

  Future<void> jumpToNavigationTarget() async {
    final target = navigationTarget;
    if (target == null || !mounted) {
      return;
    }
    // A later jump, or another conversation, takes the list over.
    final serial = ++_jumpSerial;
    bool superseded() => !mounted || serial != _jumpSerial;

    final controller = ref.read(messengerControllerProvider);
    var attempts = 0;
    while (!controller.messagesFor(conversationId).any((message) => message.id == target.messageId) &&
        controller.hasMoreHistoryFor(conversationId) &&
        attempts < 4) {
      attempts += 1;
      await controller.loadOlderConversationMessages(conversationId);
    }

    if (superseded()) {
      return;
    }

    setState(() {
      _highlightedMessageId = target.messageId;
    });

    await _scrollTo(target.messageId, superseded);
    if (superseded()) {
      return;
    }

    _highlightClearTimer?.cancel();
    _highlightClearTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted || _highlightedMessageId != target.messageId) {
        return;
      }
      setState(() => _highlightedMessageId = null);
    });
  }

  /// Scrolls the list to [messageId], one of the messages it shows (a hit
  /// of the chat's search), without marking it.
  Future<void> scrollToMessage(String messageId) {
    final serial = ++_jumpSerial;
    return _scrollTo(messageId, () => !mounted || serial != _jumpSerial);
  }

  Future<void> _scrollTo(String messageId, bool Function() superseded) async {
    final targetContext = await _buildRowOf(messageId, superseded);
    if (targetContext != null && targetContext.mounted) {
      await Scrollable.ensureVisible(
        targetContext,
        duration: VeilMotion.normal,
        curve: Curves.easeOutCubic,
        // The list runs upwards from the composer, so its leading edge is
        // the bottom: this leaves the message in the upper part of the
        // list, with what was said after it below.
        alignment: 0.82,
      );
    }
  }

  BuildContext? _rowContext(String messageId) {
    final context = messageKeys[messageId]?.currentContext;
    return context != null && context.mounted ? context : null;
  }

  /// The row of [messageId], once it is built. When it is not, the list
  /// moves towards it one screenful per frame (older messages lie further
  /// along the list, newer ones back towards its start) until the row is
  /// there. Null when the list does not show that message, or [superseded]
  /// says the jump was given up.
  Future<BuildContext?> _buildRowOf(String messageId, bool Function() superseded) async {
    // The list may not have been built with the messages just loaded.
    var framesWithoutRows = 0;
    // Far more screenfuls than five pages of history hold.
    for (var step = 0; step < 400; step++) {
      await WidgetsBinding.instance.endOfFrame;
      if (superseded()) return null;
      final built = _rowContext(messageId);
      if (built != null) return built;

      final order = shownMessageIds;
      final targetIndex = order.indexOf(messageId);
      if (targetIndex < 0) return null;
      final builtIndexes = [
        for (final (index, id) in order.indexed)
          if (_rowContext(id) != null) index,
      ];
      if (builtIndexes.isEmpty || !messageScrollController.hasClients) {
        if (++framesWithoutRows > 8) return null;
        continue;
      }
      final position = messageScrollController.position;
      final towardsOlder = targetIndex < builtIndexes.first;
      if (!towardsOlder && targetIndex < builtIndexes.last) return null;
      final next = (position.pixels + (towardsOlder ? 1 : -1) * position.viewportDimension)
          .clamp(position.minScrollExtent, position.maxScrollExtent);
      if (next == position.pixels) return null;
      position.jumpTo(next);
    }
    return null;
  }
}
