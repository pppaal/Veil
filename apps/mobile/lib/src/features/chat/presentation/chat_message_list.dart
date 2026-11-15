import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/app_state.dart';
import '../../../core/crypto/crypto_engine.dart';
import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_first_fit.dart';
import '../../../shared/presentation/veil_ui.dart';
import '../../conversations/data/conversation_models.dart';
import '../../conversations/data/veil_messenger_controller.dart';
import 'chat_message_runs.dart';
import 'message_bubble.dart';
import 'reaction_chips_row.dart';
import 'system_notice_bubble.dart';

/// The message area of a chat: a loading, failed or empty state, or the
/// messages with their reactions and, above the first, a button that loads
/// older history. Each message is built under its key in [messageKeys], so
/// the screen can scroll one into view.
///
/// Messages run in groups: one sender's messages within five minutes of
/// each other on the same day share a group, 2 px apart with the tail on the
/// last bubble only; groups are 8 apart. A day starts under its date in
/// small muted type. In a group chat the first bubble of a group carries the
/// sender's name and the last one their avatar beside it.
class ChatMessageList extends ConsumerWidget {
  const ChatMessageList({
    super.key,
    required this.conversationId,
    required this.controller,
    required this.messages,
    required this.filteredMessages,
    required this.hasMoreHistory,
    required this.isLoadingHistory,
    required this.hasSearchQuery,
    required this.scrollController,
    required this.messageKeys,
    required this.highlightedMessageId,
    required this.sentAtFormat,
    required this.onResolveAttachment,
    required this.onReact,
    this.loadFailed = false,
    this.loadFailedReason,
    this.onRetryLoad,
    this.onVerifyPeer,
    this.senderNameOf,
    this.senderHandleOf,
    this.keyboardUp = false,
    this.padding = EdgeInsets.zero,
  });

  final String conversationId;
  final VeilMessengerController controller;

  /// Every loaded message of the conversation, expired ones included.
  final List<ChatMessage> messages;

  /// The messages shown: those not expired and, while searching, matching.
  final List<ChatMessage> filteredMessages;
  final bool hasMoreHistory;
  final bool isLoadingHistory;
  final bool hasSearchQuery;
  final ScrollController scrollController;

  /// Owned by the screen; keys of messages no longer shown are dropped.
  final Map<String, GlobalKey> messageKeys;
  final String? highlightedMessageId;
  final DateFormat sentAtFormat;
  final Future<void> Function(String attachmentId) onResolveAttachment;
  final void Function(ChatMessage message) onReact;

  /// Whether the history could not be fetched; with nothing loaded the area
  /// then says so, with [loadFailedReason] when the messenger gave one, and
  /// offers [onRetryLoad].
  final bool loadFailed;
  final String? loadFailedReason;
  final VoidCallback? onRetryLoad;

  /// Opens the peer's safety number from the empty chat, before the first
  /// message; null where there is nothing to compare (a contact already
  /// verified, a group).
  final VoidCallback? onVerifyPeer;

  /// Who of a group wrote a message, as far as this device knows; null in
  /// a 1:1, where the side a bubble is on says it.
  final String? Function(ChatMessage message)? senderNameOf;

  /// The handle of who of a group wrote a message, which their avatar and
  /// the tint of their name are drawn from; null where it is not known.
  final String? Function(ChatMessage message)? senderHandleOf;

  /// The gap between two bubbles of one group, and between two groups.
  static const double runGap = 2;
  static const double groupGap = VeilSpace.xs;


  /// Whether the keyboard is open, which an empty chat answers with its
  /// compact form: the title and the button. The screen asks, from above
  /// the shell whose body no longer knows about the keyboard.
  final bool keyboardUp;

  /// Space around the messages, inside the area they scroll in.
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);

    if (messages.isEmpty && controller.isBusy) {
      return _CenteredState(child: ChatLoadingState(label: l10n.chatLoadingTitle));
    }

    if (messages.isEmpty && loadFailed) {
      return _CenteredState(
        child: VeilEmptyState.error(
          title: l10n.chatLoadFailedTitle,
          body: loadFailedReason ?? l10n.chatLoadFailedBody,
          action: onRetryLoad == null
              ? null
              : VeilButton(
                  expanded: false,
                  tone: VeilButtonTone.secondary,
                  label: l10n.commonRetry,
                  onPressed: onRetryLoad,
                ),
        ),
      );
    }

    if (messages.isEmpty) {
      // Nothing to read yet, and the composer is right below: the state says
      // what every messenger says here, that messages are end-to-end
      // encrypted, and offers the one thing worth doing before the first
      // message, comparing safety numbers. Above an open keyboard there is
      // no room for the line: the title and the button then show alone.
      Widget emptyState({required bool compact}) => VeilEmptyState(
            compact: compact,
            title: l10n.chatEmptyTitle,
            body: l10n.chatEmptyEncrypted,
            action: onVerifyPeer == null
                ? null
                : VeilButton(
                    expanded: false,
                    tone: VeilButtonTone.secondary,
                    label: l10n.chatEmptyVerifyAction,
                    onPressed: onVerifyPeer,
                  ),
          );
      return Center(
        child: VeilFirstThatFits(
          children: [
            if (!keyboardUp) emptyState(compact: false),
            SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: emptyState(compact: true),
            ),
          ],
        ),
      );
    }

    if (hasSearchQuery && filteredMessages.isEmpty) {
      return _CenteredState(
        child: VeilEmptyState(
          title: l10n.chatSearchEmptyTitle,
          body: l10n.chatSearchEmptyBody,
        ),
      );
    }

    final validIds = filteredMessages.map((message) => message.id).toSet();
    messageKeys.removeWhere((messageId, _) => !validIds.contains(messageId));

    // Newest at the bottom, where the chat opens and stays as messages
    // arrive: the list runs upwards from the composer, so a short
    // conversation sits against it and a long one starts at its end.
    final count = filteredMessages.length;
    return ListView.builder(
      controller: scrollController,
      key: PageStorageKey<String>('chat-$conversationId'),
      reverse: true,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      itemCount: count,
      padding: padding,
      itemBuilder: (context, index) => _buildMessageEntry(context, ref, count - 1 - index),
    );
  }

  Widget _buildMessageEntry(BuildContext context, WidgetRef ref, int index) {
    final l10n = AppLocalizations.of(context);
    final message = filteredMessages[index];
    // A reaction shows on its target, not as a row: the bubbles around it
    // are neighbours. The envelope's kind is the relay's word, so it only
    // decides the spacing; what is drawn is decided by the decrypted kind.
    final hidden = chatReactionHint(message);
    final previous = hidden ? null : _neighbour(index, -1);
    final next = hidden ? null : _neighbour(index, 1);
    final showLoadOlder = index == 0 && hasMoreHistory && !hasSearchQuery;
    final startsDay = !hidden && (previous == null || !sameChatDay(previous.sentAt, message.sentAt));
    final runsOn = previous != null && sameChatRun(previous, message);
    final runsInto = next != null && sameChatRun(message, next);
    final position = switch ((runsOn, runsInto)) {
      (false, false) => VeilBubblePosition.single,
      (false, true) => VeilBubblePosition.first,
      (true, true) => VeilBubblePosition.middle,
      (true, false) => VeilBubblePosition.last,
    };
    // The next day's date brings its own space above it.
    final gapBelow = hidden
        ? groupGap
        : next == null || !sameChatDay(message.sentAt, next.sentAt)
            ? 0.0
            : runsInto
                ? runGap
                : groupGap;
    final decryptFuture = controller.decryptMessage(message);
    final entry = RepaintBoundary(
      child: KeyedSubtree(
        key: messageKeys.putIfAbsent(message.id, () => GlobalKey()),
        child: FutureBuilder<DecryptedMessage>(
          future: decryptFuture,
          // Only the authenticated inner kind may render as system chrome;
          // the envelope's messageKind is set by whoever relayed it. A
          // reaction shows on its target, never as a row of its own, and one
          // whose sender is unproven (legacy) is not shown at all.
          builder: (context, snapshot) => switch (snapshot.data) {
            DecryptedMessage(
              status: DecryptStatus.ok || DecryptStatus.legacyUnauthenticated,
              messageKind: MessageKind.reaction,
            ) =>
              const SizedBox.shrink(),
            DecryptedMessage(isOk: true, messageKind: MessageKind.system) => Padding(
                padding: EdgeInsets.only(bottom: gapBelow),
                child: SystemNoticeBubble(message: message, notice: snapshot.data!),
              ),
            _ => Padding(
                padding: EdgeInsets.only(bottom: gapBelow),
                child: _buildBubbleRow(ref, message, decryptFuture, position),
              ),
          },
        ),
      ),
    );
    if (!showLoadOlder && !startsDay) return entry;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showLoadOlder)
          Center(
            child: VeilButton(
              expanded: false,
              onPressed: isLoadingHistory
                  ? null
                  : () => ref.read(messengerControllerProvider).loadOlderConversationMessages(conversationId),
              tone: VeilButtonTone.ghost,
              label: isLoadingHistory ? l10n.chatLoadingOlder : l10n.chatLoadOlder,
            ),
          ),
        if (startsDay) ChatDayDivider(day: message.sentAt, first: index == 0 && !showLoadOlder),
        entry,
      ],
    );
  }

  /// A bubble with its reactions under it, on its sender's side. In a group
  /// chat the peer's bubbles keep a column for the sender's avatar, which
  /// the last bubble of a group shows.
  Widget _buildBubbleRow(
    WidgetRef ref,
    ChatMessage message,
    Future<DecryptedMessage> decryptFuture,
    VeilBubblePosition position,
  ) {
    final group = senderNameOf != null;
    final opensRun = position == VeilBubblePosition.first || position == VeilBubblePosition.single;
    final closesRun = position == VeilBubblePosition.last || position == VeilBubblePosition.single;
    final name = message.isMine ? null : senderNameOf?.call(message);
    final handle = message.isMine ? null : senderHandleOf?.call(message);
    final bubble = _buildBubbleWithReactions(
      ref,
      message,
      decryptFuture,
      senderName: opensRun ? name : null,
      senderSeed: handle,
      position: position,
    );
    if (!group || message.isMine) return bubble;
    final Widget avatar = !closesRun || name == null
        ? const SizedBox(width: 32)
        : handle == null
            ? const VeilAvatar(name: '', seed: '', size: 32, unknown: true)
            : VeilAvatar(name: name, seed: handle, size: 32);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        avatar,
        const SizedBox(width: VeilSpace.xs),
        Expanded(child: bubble),
      ],
    );
  }

  // The nearest message before ([step] -1) or after (1) the one at [index]
  // that is not a reaction, or null.
  ChatMessage? _neighbour(int index, int step) {
    for (var i = index + step; i >= 0 && i < filteredMessages.length; i += step) {
      if (!chatReactionHint(filteredMessages[i])) return filteredMessages[i];
    }
    return null;
  }

  Widget _buildBubbleWithReactions(
    WidgetRef ref,
    ChatMessage message,
    Future<DecryptedMessage> decryptFuture, {
    required String? senderName,
    required String? senderSeed,
    required VeilBubblePosition position,
  }) {
    final bubble = MessageBubble(
      message: message,
      senderName: senderName,
      senderSeed: senderSeed,
      position: position,
      highlighted: message.id == highlightedMessageId,
      sentAtFormat: sentAtFormat,
      decryptFuture: decryptFuture,
      onResolveAttachment: onResolveAttachment,
      onCancelAttachment: message.clientMessageId == null
          ? null
          : () => ref
              .read(messengerControllerProvider)
              .cancelPendingAttachment(message.clientMessageId!),
      isResolvingAttachment: controller.isResolvingAttachment,
      attachmentDownloadError: controller.attachmentDownloadError,
      transferSnapshot: message.clientMessageId == null
          ? null
          : controller.attachmentTransferForMessage(message.clientMessageId!),
      expiryNow: controller.expiryNow,
      onRetryMessage: message.hasFailed
          ? () => ref
              .read(messengerControllerProvider)
              .retryPendingMessages(conversationId)
          : null,
    );
    final reactive = GestureDetector(
      behavior: HitTestBehavior.translucent,
      onLongPress: () => onReact(message),
      child: bubble,
    );
    if (message.reactions.isEmpty) {
      return reactive;
    }
    return Column(
      crossAxisAlignment:
          message.isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        reactive,
        ReactionChipsRow(
          message: message,
          // Watched only where a message has reactions to mark as this
          // user's own.
          myUserId: ref.watch(appSessionProvider).userId,
          onChipTap: (emoji) => controller.toggleReaction(message, emoji),
        ),
      ],
    );
  }
}

/// A loading or empty state in the middle of the message area. It scrolls
/// when the area is shorter than it is, as with the keyboard open.
class _CenteredState extends StatelessWidget {
  const _CenteredState({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: child,
        ),
      ),
    );
  }
}
