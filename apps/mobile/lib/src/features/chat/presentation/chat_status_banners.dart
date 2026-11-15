import 'package:flutter/material.dart';

import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_error_text.dart';
import '../../../shared/presentation/veil_first_fit.dart';
import '../../../shared/presentation/veil_ui.dart';
import '../../conversations/data/conversation_models.dart';
import '../../conversations/data/messenger/conversation_peer_bindings.dart';
import '../../conversations/data/veil_messenger_controller.dart';
import 'chat_room_labels.dart';

/// What sits between a chat's bar and its messages: a notice for each thing
/// the user has to decide or act on (an identity change or held account
/// that pauses the 1:1, a key change of the peer's that waits in another
/// chat, sends still waiting), each with its action inside it; then, as one
/// plain line each, the messenger's error and a running search. An error
/// has no action of its own to offer, so it is a line, not a notice. A
/// quiet chat shows nothing here: the bar carries the verified mark, and the
/// messages keep the height.
///
/// Given less height than its notices need, it shows each warning as one
/// full-bleed row (title and action), and only when even those do not fit
/// do the rows scroll.
class ChatStatusBanners extends StatelessWidget {
  const ChatStatusBanners({
    super.key,
    required this.controller,
    required this.conversationId,
    required this.conversation,
    required this.messages,
    required this.hasSearchQuery,
    required this.searching,
    required this.searchHitCount,
    required this.onReviewIdentity,
    required this.onAcknowledgeHold,
    required this.onRetryFailed,
    this.errorShownBelow = false,
  });

  final VeilMessengerController controller;
  final String conversationId;
  final ConversationPreview? conversation;

  /// Every loaded message of the conversation, expired ones included.
  final List<ChatMessage> messages;
  final bool hasSearchQuery;
  final bool searching;
  final int searchHitCount;
  final VoidCallback onReviewIdentity;
  final void Function(PeerAccountHold hold, String handle) onAcknowledgeHold;
  final VoidCallback onRetryFailed;

  /// Whether the message area already says what the messenger's error is
  /// (a history that could not be loaded), so no banner repeats it.
  final bool errorShownBelow;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final notices = _notices(l10n);
    final error = _errorLine(l10n);
    final lines = [
      if (error != null) error,
      if (hasSearchQuery) searching ? l10n.chatSearchSearching : l10n.chatSearchMatchCount(searchHitCount),
    ];
    if (notices.isEmpty && lines.isEmpty) return const SizedBox.shrink();
    return VeilFirstThatFits(
      children: [
        // A gap under the last notice as over the first: a message scrolled
        // up to the notices stops short of them and never touches one (a
        // grey bubble cut off under a grey notice reads as one shape).
        Padding(
          padding: const EdgeInsets.symmetric(vertical: VeilSpace.xs),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (index, notice) in notices.indexed) ...[
                if (index > 0) const SizedBox(height: VeilSpace.xs),
                VeilNotice(
                  title: notice.title,
                  message: notice.message,
                  tone: notice.tone,
                  actionLabel: notice.actionLabel,
                  onAction: notice.onAction,
                ),
              ],
              for (final (index, line) in lines.indexed)
                Padding(
                  padding: EdgeInsets.fromLTRB(
                      VeilSpace.md, notices.isEmpty && index == 0 ? 0 : VeilSpace.xs, VeilSpace.md, 0),
                  child: _line(context, line),
                ),
            ],
          ),
        ),
        // With the keyboard up on a small phone the notices above would be
        // cut off, the action of the first among them: each warning then
        // keeps its title and its action in one row. A strip of page under
        // the rows, outside their scrolling, keeps the messages off them.
        Padding(
          padding: const EdgeInsets.only(bottom: VeilSpace.xxs),
          child: _ScrollingRows(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (notices.isNotEmpty)
                  VeilGroup(
                    // Grey rows edge to edge: a line that started at the text
                    // would leave a notch of page colour at the start.
                    inset: 0,
                    children: [
                      for (final notice in notices)
                        VeilNotice(
                          dense: true,
                          title: notice.title,
                          message: notice.message,
                          tone: notice.tone,
                          actionLabel: notice.actionLabel,
                          onAction: notice.onAction,
                        ),
                    ],
                  ),
                for (final line in lines)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: VeilSpace.md, vertical: VeilSpace.xxs),
                    child: _line(context, line, maxLines: 2),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _line(BuildContext context, String text, {int? maxLines}) {
    return Text(
      text,
      maxLines: maxLines,
      overflow: maxLines == null ? null : TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: context.veilPalette.textMuted),
    );
  }

  /// The messenger's error, in the app's words, when this chat should say
  /// it: not the note about a dropped link (this chat's waiting sends below
  /// say that, or it is another chat's business), and not when the message
  /// area already says why nothing loaded.
  String? _errorLine(AppLocalizations l10n) {
    final error = controller.errorMessage;
    if (error == null || controller.errorIsRelayInterruption || errorShownBelow) return null;
    return veilErrorText(l10n, error);
  }

  /// The warnings, most pressing first.
  List<_Notice> _notices(AppLocalizations l10n) {
    final conversation = this.conversation;
    final isDirect = conversation?.type == ConversationType.direct;
    final pendingCount = controller.pendingCountFor(conversationId);
    final failedCount = messages.where((message) => message.hasFailed).length;
    final uploadingCount =
        messages.where((message) => message.deliveryState == MessageDeliveryState.uploading).length;
    final queuedCount = messages.where((message) => message.deliveryState == MessageDeliveryState.pending).length;
    final nextRetryAt = controller.nextRetryAtForConversation(conversationId);
    final accountHold = isDirect ? controller.peerAccountHoldFor(conversationId) : null;
    final connected = controller.realtimeConnected;
    final changeHere = isDirect && controller.pendingIdentityChangeFor(conversationId) != null;
    // The peer presented another key in a conversation they share with the
    // user (a group), which holds it for review. This 1:1 still talks to
    // the key it pinned, and says where the question is open.
    final changeElsewhere = conversation != null &&
        isDirect &&
        !changeHere &&
        controller.pendingIdentityChangeAbout(conversation.recipientBundle.userId) != null;

    return [
      // Only a 1:1 conversation pauses; a group just leaves the device out.
      if (changeHere)
        _Notice(
          title: l10n.chatIdentityChangedTitle,
          message: l10n.chatIdentityChangedBody,
          tone: VeilTone.warn,
          actionLabel: l10n.chatIdentityChangedReview,
          onAction: onReviewIdentity,
        ),
      if (changeElsewhere)
        _Notice(
          title: l10n.chatIdentityChangedElsewhereTitle,
          message: l10n.chatIdentityChangedElsewhereBody,
          tone: VeilTone.warn,
          actionLabel: l10n.chatIdentityChangedReview,
          onAction: onReviewIdentity,
        ),
      // Listed under a handle this device knows as another account, under
      // the user's own handle as another account, or under one no honest
      // relay issues: nothing is sent or opened until the user says this is
      // the account they want to talk to.
      if (accountHold != null)
        _Notice(
          title: switch (accountHold.reason) {
            PeerAccountHoldReason.otherAccount => l10n.chatAccountHoldOtherTitle,
            PeerAccountHoldReason.unissuedHandle => l10n.chatAccountHoldUnissuedTitle,
            PeerAccountHoldReason.ownHandle => l10n.chatAccountHoldOwnTitle,
          },
          message: switch (accountHold.reason) {
            PeerAccountHoldReason.otherAccount =>
              l10n.chatAccountHoldOtherBody(accountHold.known?.handle ?? conversation?.peerHandle ?? ''),
            PeerAccountHoldReason.unissuedHandle => l10n.chatAccountHoldUnissuedBody,
            PeerAccountHoldReason.ownHandle => l10n.chatAccountHoldOwnBody(conversation?.peerHandle ?? ''),
          },
          tone: VeilTone.warn,
          actionLabel: l10n.chatAccountHoldAcknowledge,
          onAction: () => onAcknowledgeHold(accountHold, conversation?.peerHandle ?? ''),
        ),
      if (pendingCount > 0)
        _Notice(
          title: !connected
              ? l10n.chatBannerRelayReconnecting
              : failedCount > 0
                  ? l10n.chatBannerDeliveryStalled
                  : l10n.chatBannerQueuedLocally,
          message: !connected
              ? networkRecoveryMessage(
                  l10n: l10n,
                  failedCount: failedCount,
                  queuedCount: queuedCount,
                  uploadingCount: uploadingCount,
                  nextRetryAt: nextRetryAt,
                )
              : failedCount > 0
                  ? l10n.chatBannerFailedSends(failedCount)
                  : uploadingCount > 0
                      ? l10n.chatBannerUploadingAttachments(uploadingCount)
                      : l10n.chatBannerQueuedMessages(queuedCount),
          tone: failedCount > 0
              ? VeilTone.danger
              : !connected
                  ? VeilTone.warn
                  : VeilTone.info,
          actionLabel: failedCount > 0 ? l10n.chatRetryFailedSendsAction : null,
          onAction: failedCount > 0 ? onRetryFailed : null,
        ),
    ];
  }
}

/// The one-row warnings in the height they are given: they scroll, under a
/// scrollbar that stays in view, when there are more than fit.
class _ScrollingRows extends StatefulWidget {
  const _ScrollingRows({required this.child});

  final Widget child;

  @override
  State<_ScrollingRows> createState() => _ScrollingRowsState();
}

class _ScrollingRowsState extends State<_ScrollingRows> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      controller: _scroll,
      thumbVisibility: true,
      child: SingleChildScrollView(controller: _scroll, child: widget.child),
    );
  }
}

class _Notice {
  const _Notice({
    required this.title,
    required this.message,
    required this.tone,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String message;
  final VeilTone tone;
  final String? actionLabel;
  final VoidCallback? onAction;
}
