import 'package:flutter/material.dart';

import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_ui.dart';
import '../../conversations/data/conversation_models.dart';
import '../../conversations/data/messenger/conversation_peer_bindings.dart';
import '../../conversations/data/veil_messenger_controller.dart';
import 'chat_room_labels.dart';

/// What sits between a chat's header and its messages: the verified mark,
/// the relay/history/search metrics, and a banner for each thing the user
/// should know about: the history window, an identity change or held
/// account that pauses the 1:1, an error, sends still waiting, a search.
class ChatStatusBanners extends StatelessWidget {
  const ChatStatusBanners({
    super.key,
    required this.controller,
    required this.conversationId,
    required this.conversation,
    required this.messages,
    required this.hasMoreHistory,
    required this.isLoadingHistory,
    required this.peerVerified,
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
  final bool hasMoreHistory;
  final bool isLoadingHistory;

  /// Whether every pinned device of the 1:1 peer was verified out of band.
  final bool peerVerified;
  final bool hasSearchQuery;
  final bool searching;
  final int searchHitCount;
  final VoidCallback onReviewIdentity;
  final void Function(PeerAccountHold hold, String handle) onAcknowledgeHold;
  final VoidCallback onRetryFailed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDirect = conversation?.type == ConversationType.direct;
    final pendingCount = controller.pendingCountFor(conversationId);
    final failedCount = messages.where((message) => message.hasFailed).length;
    final uploadingCount = messages
        .where((message) =>
            message.deliveryState == MessageDeliveryState.uploading)
        .length;
    final queuedCount = messages
        .where(
            (message) => message.deliveryState == MessageDeliveryState.pending)
        .length;
    final nextRetryAt = controller.nextRetryAtForConversation(conversationId);
    final historyBanner = !hasSearchQuery && messages.isNotEmpty
        ? historyWindowBannerSpec(
            l10n: l10n,
            isLoadingHistory: isLoadingHistory,
            hasMoreHistory: hasMoreHistory,
          )
        : null;
    final accountHold = isDirect ? controller.peerAccountHoldFor(conversationId) : null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (peerVerified && isDirect) ...[
          const SizedBox(height: VeilSpace.xs),
          Align(
            alignment: Alignment.centerLeft,
            child: VeilStatusPill(label: l10n.chatPeerVerified, tone: VeilBannerTone.good),
          ),
        ],
        const SizedBox(height: VeilSpace.sm),
        VeilMetricStrip(
          items: [
            VeilMetricItem(
              label: l10n.chatMetricRelay,
              value: controller.realtimeConnected
                  ? l10n.chatMetricRelayLinked
                  : l10n.chatMetricRelayRecovering,
            ),
            VeilMetricItem(
              label: l10n.chatMetricLoaded,
              value: '${messages.length}',
            ),
            VeilMetricItem(
              label: l10n.chatMetricHistory,
              value: historyWindowLabel(
                l10n: l10n,
                isLoadingHistory: isLoadingHistory,
                hasMoreHistory: hasMoreHistory,
              ),
            ),
            VeilMetricItem(
              label: l10n.chatMetricSearch,
              value: hasSearchQuery
                  ? l10n.chatMetricSearchHits(searchHitCount)
                  : l10n.chatMetricSearchIdle,
            ),
          ],
        ),
        if (historyBanner != null) ...[
          const SizedBox(height: VeilSpace.sm),
          VeilInlineBanner(
            title: historyBanner.title,
            message: historyBanner.message,
            tone: historyBanner.tone,
            icon: historyBanner.icon,
          ),
        ],
        // Only a 1:1 conversation pauses; a group just leaves the device out.
        if (isDirect && controller.pendingIdentityChangeFor(conversationId) != null) ...[
          const SizedBox(height: VeilSpace.sm),
          VeilInlineBanner(
            title: l10n.chatIdentityChangedTitle,
            message: l10n.chatIdentityChangedBody,
            tone: VeilBannerTone.warn,
            icon: Icons.gpp_maybe_outlined,
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: onReviewIdentity,
              child: Text(l10n.chatIdentityChangedReview),
            ),
          ),
        ],
        // Listed under a handle this device knows as another account, under
        // the user's own handle as another account, or under one no honest
        // relay issues: nothing is sent or opened until the user says this is
        // the account they want to talk to.
        if (accountHold != null) ...[
          const SizedBox(height: VeilSpace.sm),
          VeilInlineBanner(
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
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => onAcknowledgeHold(accountHold, conversation?.peerHandle ?? ''),
              child: Text(l10n.chatAccountHoldAcknowledge),
            ),
          ),
        ],
        if (controller.errorMessage != null) ...[
          const SizedBox(height: VeilSpace.sm),
          VeilInlineBanner(
            title: l10n.chatBannerConversationIssue,
            message: controller.errorMessage!,
            tone: VeilBannerTone.danger,
          ),
        ],
        if (pendingCount > 0) ...[
          const SizedBox(height: VeilSpace.sm),
          VeilInlineBanner(
            title: !controller.realtimeConnected
                ? l10n.chatBannerRelayReconnecting
                : failedCount > 0
                    ? l10n.chatBannerDeliveryStalled
                    : l10n.chatBannerQueuedLocally,
            message: !controller.realtimeConnected
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
            tone: !controller.realtimeConnected
                ? VeilBannerTone.warn
                : failedCount > 0
                    ? VeilBannerTone.warn
                    : VeilBannerTone.info,
          ),
          if (failedCount > 0)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(top: VeilSpace.xs),
                child: TextButton(
                  onPressed: onRetryFailed,
                  child: Text(l10n.chatRetryFailedSendsAction),
                ),
              ),
            ),
        ],
        if (hasSearchQuery) ...[
          const SizedBox(height: VeilSpace.sm),
          VeilInlineBanner(
            title: searching
                ? l10n.chatSearchBannerSearchingTitle
                : l10n.chatSearchBannerIdleTitle,
            message: searching
                ? l10n.chatSearchBannerSearchingBody
                : searchHitCount == 0
                    ? l10n.chatSearchBannerEmptyBody
                    : l10n.chatSearchBannerResultBody(searchHitCount),
            tone: VeilBannerTone.info,
            icon: Icons.manage_search_rounded,
          ),
        ],
      ],
    );
  }
}
