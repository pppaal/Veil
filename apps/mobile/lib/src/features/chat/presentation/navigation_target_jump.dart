import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_state.dart';
import '../../../core/theme/veil_theme.dart';
import '../../conversations/data/conversation_models.dart';

/// Brings the message a navigation target names into view: loads up to four
/// pages of older history until it is there, highlights it, scrolls to it,
/// and drops the highlight two seconds later.
mixin NavigationTargetJump<W extends ConsumerStatefulWidget> on ConsumerState<W> {
  /// The key each shown message is built under, kept by the message list.
  final Map<String, GlobalKey> messageKeys = <String, GlobalKey>{};
  Timer? _highlightClearTimer;
  String? _highlightedMessageId;

  /// The conversation the chat shows.
  String get conversationId;

  /// The message to bring into view, if any.
  MessageNavigationTarget? get navigationTarget;

  String? get highlightedMessageId => _highlightedMessageId;

  /// Forgets the highlight and the keys, as when the chat switches to
  /// another conversation.
  void resetNavigationTarget() {
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

    final controller = ref.read(messengerControllerProvider);
    var attempts = 0;
    while (!controller.messagesFor(conversationId).any((message) => message.id == target.messageId) &&
        controller.hasMoreHistoryFor(conversationId) &&
        attempts < 4) {
      attempts += 1;
      await controller.loadOlderConversationMessages(conversationId);
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _highlightedMessageId = target.messageId;
    });

    await Future<void>.delayed(const Duration(milliseconds: 24));
    final targetContext = messageKeys[target.messageId]?.currentContext;
    if (targetContext != null && targetContext.mounted) {
      await Scrollable.ensureVisible(
        targetContext,
        duration: VeilMotion.normal,
        curve: Curves.easeOutCubic,
        alignment: 0.18,
      );
    }

    _highlightClearTimer?.cancel();
    _highlightClearTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted || _highlightedMessageId != target.messageId) {
        return;
      }
      setState(() => _highlightedMessageId = null);
    });
  }
}
