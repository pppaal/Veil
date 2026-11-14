import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_ui.dart';
import 'conversation_list_labels.dart';
import 'conversation_list_parts.dart';

/// The conversation list as the wide layout shows it, beside the open chat:
/// the account and relay state, the local search with its filters, the
/// conversations, and the messages a search found. A phone shows the same
/// content first (conversation_list_phone.dart).
class ConversationListPane extends StatelessWidget {
  const ConversationListPane({super.key, required this.view});

  final ConversationListView view;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.veilPalette;
    final session = view.session;
    final controller = view.controller;
    final conversations = view.conversations;
    final searchController = view.searchController;
    final hasSearchQuery = view.hasSearchQuery;
    final connected = controller.realtimeConnected;
    final children = <Widget>[
      VeilHeroPanel(
        eyebrow: l10n.conversationsHeroEyebrow,
        title: session.displayName?.isNotEmpty == true
            ? session.displayName!
            : '@${session.handle ?? 'unbound'}',
        body: connected ? l10n.conversationsRelayConnectedBody : l10n.conversationsRelayIdleBody,
        bottom: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            VeilStatusPill(
              label: connected ? l10n.conversationsRelayLinked : l10n.conversationsRelayIdle,
              tone: connected ? VeilBannerTone.good : VeilBannerTone.warn,
            ),
            VeilStatusPill(label: l10n.conversationsCount(conversations.length)),
            VeilStatusPill(label: l10n.conversationsNoBackup),
          ],
        ),
      ),
      const SizedBox(height: VeilSpace.md),
      VeilMetricStrip(
        items: [
          VeilMetricItem(
            label: l10n.chatMetricRelay,
            value: connected ? l10n.chatMetricRelayLinked : l10n.conversationsMetricIdle,
          ),
          VeilMetricItem(
            label: l10n.conversationsMetricLocalSearch,
            value: hasSearchQuery ? l10n.conversationsMetricSearchActive : l10n.conversationsMetricSearchReady,
          ),
          VeilMetricItem(
            label: l10n.conversationsTitle,
            value: '${conversations.length}',
          ),
        ],
      ),
      if (controller.isBusy && controller.errorMessage == null) ...[
        const SizedBox(height: VeilSpace.md),
        VeilInlineBanner(
          title: l10n.conversationsRefreshingTitle,
          message: l10n.conversationsRefreshingBody,
          tone: VeilBannerTone.info,
          icon: Icons.sync_rounded,
        ),
      ],
      if (controller.errorMessage != null) ...[
        const SizedBox(height: VeilSpace.md),
        VeilInlineBanner(
          title: l10n.conversationsSyncIssueTitle,
          message: controller.errorMessage!,
          tone: VeilBannerTone.danger,
        ),
      ],
      const SizedBox(height: VeilSpace.md),
      VeilFieldBlock(
        label: l10n.conversationsSearchIndexLabel,
        caption: l10n.conversationsSearchIndexCaption,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: searchController,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search_rounded),
                hintText: l10n.conversationsSearchFieldHint,
                suffixIcon: !hasSearchQuery
                    ? null
                    : IconButton(
                        tooltip: l10n.chatSearchClearTooltip,
                        onPressed: searchController.clear,
                        icon: const Icon(Icons.close_rounded),
                      ),
              ),
            ),
            if (hasSearchQuery) ...[
              const SizedBox(height: VeilSpace.sm),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: conversationSearchFilterChips(l10n, view),
              ),
            ],
          ],
        ),
      ),
      if (hasSearchQuery) ...[
        const SizedBox(height: VeilSpace.md),
        VeilInlineBanner(
          title: view.searchingArchive ? l10n.chatSearchBannerSearchingTitle : l10n.conversationsSearchActiveTitle,
          message: view.searchingArchive
              ? l10n.conversationsSearchScanningBody
              : l10n.conversationsSearchFoundBody(conversations.length, view.archiveResults.length),
          tone: VeilBannerTone.info,
          icon: Icons.manage_search_rounded,
        ),
      ],
      const SizedBox(height: VeilSpace.md),
      VeilSectionLabel(
        l10n.conversationsSectionLabel,
        trailing: hasSearchQuery
            ? Text(
                l10n.conversationsMatchCount(conversations.length),
                style: Theme.of(context).textTheme.bodySmall,
              )
            : null,
      ),
      const SizedBox(height: VeilSpace.sm),
    ];

    if (conversations.isEmpty && controller.isBusy) {
      children.addAll(const [
        SizedBox(height: VeilSpace.xl),
        ConversationListSkeleton(),
      ]);
    } else if (conversations.isEmpty) {
      children.add(
        Padding(
          padding: const EdgeInsets.only(top: 72),
          child: VeilEmptyState(
            title: hasSearchQuery ? l10n.conversationsNoMatchTitle : l10n.conversationsNoneYetTitle,
            body: hasSearchQuery ? l10n.conversationsNoMatchBody : l10n.conversationsNoneYetBody,
            icon: hasSearchQuery ? Icons.search_off_rounded : Icons.forum_outlined,
            action: VeilButton(
              onPressed: () => context.push('/start-chat'),
              label: l10n.conversationsStartDirect,
              tone: VeilButtonTone.secondary,
            ),
          ),
        ),
      );
    } else {
      children.addAll(
        conversations.map((item) {
          final isSelected = item.id == view.selectedConversationId;
          final pendingCount = controller.pendingCountFor(item.id);
          final title = item.peerDisplayName ?? item.peerHandle;
          return Padding(
            padding: const EdgeInsets.only(bottom: VeilSpace.sm),
            child: RepaintBoundary(
              child: AnimatedContainer(
                duration: VeilMotion.normal,
                curve: Curves.easeOutCubic,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(VeilRadius.lg),
                  boxShadow: isSelected ? VeilElevation.raised : null,
                ),
                child: Theme(
                  data: Theme.of(context).copyWith(
                    cardTheme: Theme.of(context).cardTheme.copyWith(
                          color: isSelected
                              ? palette.surfaceRaised
                              : Theme.of(context).cardTheme.color,
                        ),
                  ),
                  child: VeilConversationCard(
                    title: title,
                    handle: item.peerHandle,
                    subtitle: conversationPreviewLine(l10n, item, controller),
                    timestamp: view.timeFormat.format(item.updatedAt),
                    semanticLabel: l10n.conversationsRowSemantics(title),
                    selected: isSelected,
                    meta: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        VeilStatusPill(label: l10n.conversationsPillDirect),
                        if (pendingCount > 0)
                          VeilStatusPill(
                            label: l10n.conversationsPillQueued(pendingCount),
                            tone: VeilBannerTone.warn,
                          ),
                      ],
                    ),
                    expiryLabel: conversationExpiryLabel(l10n, item, controller),
                    onTap: () => view.onSelectConversation(item.id),
                  ),
                ),
              ),
            ),
          );
        }),
      );
    }

    if (hasSearchQuery) {
      children.addAll(messageSearchResultSection(context, view));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: RefreshIndicator(
            onRefresh: controller.refreshConversations,
            child: ListView(
              key: const PageStorageKey<String>('conversation-list-scroll'),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              children: [
                ...children,
                const SizedBox(height: VeilSpace.sm),
                VeilButton(
                  onPressed: () => context.push('/start-chat'),
                  label: l10n.conversationsStartDirect,
                  tone: VeilButtonTone.secondary,
                  icon: Icons.add_comment_outlined,
                ),
                const SizedBox(height: VeilSpace.sm),
                VeilButton(
                  onPressed: () => context.push('/start-group'),
                  label: l10n.conversationsStartGroup,
                  tone: VeilButtonTone.secondary,
                  icon: Icons.group_add_outlined,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
