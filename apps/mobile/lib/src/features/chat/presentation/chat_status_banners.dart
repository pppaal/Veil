import 'package:flutter/material.dart';

import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_ui.dart';
import '../../conversations/data/conversation_models.dart';
import '../../conversations/data/messenger/conversation_peer_bindings.dart';
import '../../conversations/data/veil_messenger_controller.dart';
import 'chat_room_labels.dart';

/// What sits between a chat's header and its messages: a banner for each
/// thing the user has to decide or should be warned about (an identity
/// change or held account that pauses the 1:1, an error, sends still
/// waiting) and a line about a running search.
///
/// The wide layout adds the verified mark, the relay/history/search metrics
/// and the history window around them. [compact], the phone layout, shows
/// the warnings only, each with its action inside it: the bar above carries
/// the verified mark, and the messages keep the height.
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
    this.compact = false,
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
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final notices = _notices(l10n);
    if (compact) return _buildCompact(context, l10n, notices);

    final isDirect = conversation?.type == ConversationType.direct;
    final historyBanner = !hasSearchQuery && messages.isNotEmpty
        ? historyWindowBannerSpec(
            l10n: l10n,
            isLoadingHistory: isLoadingHistory,
            hasMoreHistory: hasMoreHistory,
          )
        : null;

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
        for (final notice in notices) ...[
          const SizedBox(height: VeilSpace.sm),
          VeilInlineBanner(
            title: notice.title,
            message: notice.message,
            tone: notice.tone,
            icon: notice.icon,
          ),
          if (notice.actionLabel != null)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: EdgeInsets.only(top: notice.actionGap),
                child: TextButton(
                  onPressed: notice.onAction,
                  child: Text(notice.actionLabel!),
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

  Widget _buildCompact(BuildContext context, AppLocalizations l10n, List<_Notice> notices) {
    if (notices.isEmpty && !hasSearchQuery) return const SizedBox.shrink();
    final palette = context.veilPalette;
    return Padding(
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
              child: Row(
                children: [
                  Icon(Icons.manage_search_rounded, size: VeilIconSize.sm, color: palette.textMuted),
                  const SizedBox(width: VeilSpace.xs),
                  Expanded(
                    child: Text(
                      searching ? l10n.chatSearchBannerSearchingTitle : l10n.chatSearchMatchCount(searchHitCount),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: palette.textMuted),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// The warnings both layouts show, most pressing first.
  List<_Notice> _notices(AppLocalizations l10n) {
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
    final accountHold = isDirect ? controller.peerAccountHoldFor(conversationId) : null;
    final connected = controller.realtimeConnected;

    return [
      // Only a 1:1 conversation pauses; a group just leaves the device out.
      if (isDirect && controller.pendingIdentityChangeFor(conversationId) != null)
        _Notice(
          title: l10n.chatIdentityChangedTitle,
          message: l10n.chatIdentityChangedBody,
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
      if (controller.errorMessage != null)
        _Notice(
          title: l10n.chatBannerConversationIssue,
          message: controller.errorMessage!,
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
          actionGap: VeilSpace.xs,
        ),
    ];
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
    this.actionGap = 0,
  });

  final String title;
  final String message;
  final VeilBannerTone tone;
  final IconData? icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Space between the banner and its button in the wide layout.
  final double actionGap;
}
