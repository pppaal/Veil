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
import 'animated_bubble_entry.dart';
import 'message_bubble.dart';
import 'reaction_chips_row.dart';
import 'system_notice_bubble.dart';

/// The message area of a chat: a loading, failed or empty state, or the
/// messages with their reactions and, above the first, a button that loads
/// older history. Each message is built under its key in [messageKeys], so
/// the screen can scroll one into view.
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

  /// Space around the messages, inside the area they scroll in.
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);

    if (messages.isEmpty && controller.isBusy) {
      return _CenteredState(
        child: VeilLoadingBlock(
          title: l10n.chatLoadingTitle,
          body: l10n.chatLoadingBody,
        ),
      );
    }

    if (messages.isEmpty && loadFailed) {
      return _CenteredState(
        child: VeilEmptyState(
          title: l10n.chatLoadFailedTitle,
          body: loadFailedReason ?? l10n.chatLoadFailedBody,
          icon: Icons.cloud_off_rounded,
          action: onRetryLoad == null
              ? null
              : VeilButton(
                  expanded: false,
                  tone: VeilButtonTone.secondary,
                  icon: Icons.refresh_rounded,
                  label: l10n.commonRetry,
                  onPressed: onRetryLoad,
                ),
        ),
      );
    }

    if (messages.isEmpty) {
      // Nothing to read yet, and the composer is right below: the state says
      // what is true of whatever is sent here, and offers the one thing
      // worth doing before the first message, comparing safety numbers.
      // Above an open keyboard there is no room for the icon and the space
      // around it: the same words and button then show without them.
      Widget emptyState({required bool compact}) => VeilEmptyState(
            compact: compact,
            title: l10n.chatEmptyTitle,
            body: l10n.chatEmptyBody,
            icon: Icons.lock_outline_rounded,
            action: onVerifyPeer == null
                ? null
                : VeilButton(
                    expanded: false,
                    tone: VeilButtonTone.secondary,
                    icon: Icons.verified_user_outlined,
                    label: l10n.chatEmptyVerifyAction,
                    onPressed: onVerifyPeer,
                  ),
          );
      return Center(
        child: VeilFirstThatFits(
          children: [
            emptyState(compact: false),
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
          icon: Icons.search_off_rounded,
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
    final showLoadOlder = index == 0 && hasMoreHistory && !hasSearchQuery;
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
            DecryptedMessage(isOk: true, messageKind: MessageKind.system) =>
              SystemNoticeBubble(message: message, notice: snapshot.data!),
            _ => AnimatedBubbleEntry(
                fromRight: message.isMine,
                child: _buildBubbleWithReactions(ref, message, decryptFuture, _senderNameAt(index)),
              ),
          },
        ),
      ),
    );
    final gap = EdgeInsets.only(bottom: index == filteredMessages.length - 1 ? 0 : VeilSpace.sm);
    if (!showLoadOlder) {
      return Padding(padding: gap, child: entry);
    }

    return Padding(
      padding: gap,
      child: Column(
        children: [
          VeilButton(
            onPressed: isLoadingHistory
                ? null
                : () => ref
                    .read(messengerControllerProvider)
                    .loadOlderConversationMessages(conversationId),
            tone: VeilButtonTone.secondary,
            label: isLoadingHistory ? l10n.chatLoadingOlder : l10n.chatLoadOlder,
          ),
          const SizedBox(height: VeilSpace.sm),
          entry,
        ],
      ),
    );
  }

  // Named on the first of a sender's messages in a row, as far as the rows
  // tell: the one before is someone else's.
  String? _senderNameAt(int index) {
    final message = filteredMessages[index];
    final name = message.isMine ? null : senderNameOf?.call(message);
    if (name == null || index == 0) return name;
    final previous = filteredMessages[index - 1];
    return previous.senderDeviceId == message.senderDeviceId && !previous.isLocalNotice ? null : name;
  }

  Widget _buildBubbleWithReactions(
    WidgetRef ref,
    ChatMessage message,
    Future<DecryptedMessage> decryptFuture,
    String? senderName,
  ) {
    final bubble = MessageBubble(
      message: message,
      senderName: senderName,
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
