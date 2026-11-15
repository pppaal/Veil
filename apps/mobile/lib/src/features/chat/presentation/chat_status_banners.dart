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

/// What sits between a chat's bar and its messages: a banner for each thing
/// the user has to decide or should be warned about (an identity change or
/// held account that pauses the 1:1, a key change of the peer's that waits
/// in another chat, an error, sends still waiting), each with its action
/// inside it, and a line about a running search. A quiet chat shows nothing
/// here: the bar carries the verified mark, and the messages keep the height.
///
/// Given less height than its banners need, it shows each warning as one
/// row (title and action), and only when even those do not fit do the rows
/// scroll.
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final notices = _notices(l10n);
    if (notices.isEmpty && !hasSearchQuery) return const SizedBox.shrink();
    return VeilFirstThatFits(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(VeilSpace.sm, VeilSpace.xs, VeilSpace.sm, 0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (index, notice) in notices.indexed) ...[
                if (index > 0) const SizedBox(height: VeilSpace.xs),
                VeilInlineBanner(
                  dense: true,
                  title: notice.title,
                  message: notice.message,
                  tone: notice.tone,
                  icon: notice.icon,
                  actionLabel: notice.actionLabel,
                  onAction: notice.onAction,
                ),
              ],
              if (hasSearchQuery)
                Padding(
                  padding: EdgeInsets.fromLTRB(VeilSpace.xxs, notices.isEmpty ? 0 : VeilSpace.xs, VeilSpace.xxs, 0),
                  child: _searchLine(context, l10n),
                ),
            ],
          ),
        ),
        // With the keyboard up on a small phone the banners above would be
        // cut off, the action of the first among them: each warning then
        // keeps its title and its action in one row.
        _ScrollingRows(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final notice in notices)
                VeilNoticeRow(
                  title: notice.title,
                  message: notice.message,
                  tone: notice.tone,
                  icon: notice.icon,
                  actionLabel: notice.actionLabel,
                  onAction: notice.onAction,
                ),
              if (hasSearchQuery)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: VeilSpace.md, vertical: VeilSpace.xxs),
                  child: _searchLine(context, l10n),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _searchLine(BuildContext context, AppLocalizations l10n) {
    final palette = context.veilPalette;
    return Row(
      children: [
        Icon(Icons.manage_search_rounded, size: VeilIconSize.sm, color: palette.textMuted),
        const SizedBox(width: VeilSpace.xs),
        Expanded(
          child: Text(
            searching ? l10n.chatSearchSearching : l10n.chatSearchMatchCount(searchHitCount),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: palette.textMuted),
          ),
        ),
      ],
    );
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
    final error = controller.errorMessage;
    // The note about the dropped relay link is this chat's own "sends are
    // waiting" below when it has any, and another chat's business when not.
    final showError = error != null && !controller.errorIsRelayInterruption;

    return [
      // Only a 1:1 conversation pauses; a group just leaves the device out.
      if (changeHere)
        _Notice(
          title: l10n.chatIdentityChangedTitle,
          message: l10n.chatIdentityChangedBody,
          tone: VeilBannerTone.warn,
          icon: Icons.gpp_maybe_outlined,
          actionLabel: l10n.chatIdentityChangedReview,
          onAction: onReviewIdentity,
        ),
      if (changeElsewhere)
        _Notice(
          title: l10n.chatIdentityChangedElsewhereTitle,
          message: l10n.chatIdentityChangedElsewhereBody,
          tone: VeilBannerTone.warn,
          icon: Icons.gpp_maybe_outlined,
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
          tone: VeilBannerTone.danger,
          icon: Icons.person_off_outlined,
          actionLabel: l10n.chatAccountHoldAcknowledge,
          onAction: () => onAcknowledgeHold(accountHold, conversation?.peerHandle ?? ''),
        ),
      if (showError)
        _Notice(
          title: l10n.chatBannerConversationIssue,
          message: veilErrorText(l10n, error),
          tone: VeilBannerTone.danger,
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
          tone: !connected || failedCount > 0 ? VeilBannerTone.warn : VeilBannerTone.info,
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
    this.icon,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String message;
  final VeilBannerTone tone;
  final IconData? icon;
  final String? actionLabel;
  final VoidCallback? onAction;
}
