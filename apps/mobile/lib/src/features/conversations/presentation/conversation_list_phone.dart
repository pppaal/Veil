import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_ui.dart';
import '../data/conversation_models.dart';
import 'conversation_list_labels.dart';
import 'conversation_list_parts.dart';

/// The conversation list on a phone, content first: one line of status (the
/// relay, how many conversations, no backup), the search field, then the
/// conversations. Search filters and the messages a search found appear
/// only while a query is typed, and a sync error only while there is one.
class ConversationListPhone extends StatelessWidget {
  const ConversationListPhone({super.key, required this.view});

  final ConversationListView view;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final palette = context.veilPalette;
    final controller = view.controller;
    final conversations = view.conversations;
    final hasSearchQuery = view.hasSearchQuery;
    final loadingFirstList = conversations.isEmpty && controller.isBusy;

    return RefreshIndicator(
      onRefresh: controller.refreshConversations,
      child: ListView(
        key: const PageStorageKey<String>('conversation-list-scroll'),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(VeilSpace.sm, VeilSpace.xs, VeilSpace.sm, VeilSpace.md),
        children: [
          _StatusLine(
            connected: controller.realtimeConnected,
            refreshing: controller.isBusy && controller.errorMessage == null,
            conversationCount: controller.conversations.length,
          ),
          const SizedBox(height: VeilSpace.xs),
          _SearchField(controller: view.searchController, hasQuery: hasSearchQuery),
          if (hasSearchQuery) ...[
            const SizedBox(height: VeilSpace.xxs),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final chip in conversationSearchFilterChips(l10n, view))
                    Padding(padding: const EdgeInsets.only(right: VeilSpace.xs), child: chip),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: VeilSpace.xxs),
              child: Text(
                l10n.conversationsSearchLocalNote,
                style: theme.textTheme.bodySmall?.copyWith(color: palette.textSubtle),
              ),
            ),
          ],
          if (controller.errorMessage != null) ...[
            const SizedBox(height: VeilSpace.xs),
            VeilInlineBanner(
              dense: true,
              title: l10n.conversationsSyncIssueTitle,
              message: controller.errorMessage!,
              tone: VeilBannerTone.danger,
            ),
          ],
          if (hasSearchQuery) ...[
            const SizedBox(height: VeilSpace.sm),
            VeilSectionLabel(
              l10n.conversationsSectionLabel,
              trailing: Text(
                l10n.conversationsMatchCount(conversations.length),
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
          const SizedBox(height: VeilSpace.xs),
          if (loadingFirstList)
            const ConversationListSkeleton()
          else if (conversations.isEmpty)
            VeilEmptyState(
              title: hasSearchQuery ? l10n.conversationsNoMatchTitle : l10n.conversationsNoneYetTitle,
              body: hasSearchQuery ? l10n.conversationsNoMatchBody : l10n.conversationsNoneYetBody,
              icon: hasSearchQuery ? Icons.search_off_rounded : Icons.forum_outlined,
              action: VeilButton(
                expanded: false,
                onPressed: () => context.push('/start-chat'),
                label: l10n.conversationsStartDirect,
                tone: VeilButtonTone.secondary,
                icon: Icons.add_comment_outlined,
              ),
            )
          else
            for (final item in conversations)
              RepaintBoundary(
                child: VeilConversationCard(
                  dense: true,
                  title: item.peerDisplayName ?? item.peerHandle,
                  handle: item.peerHandle,
                  subtitle: conversationPreviewLine(l10n, item, controller),
                  timestamp: view.timeFormat.format(item.updatedAt),
                  semanticLabel: l10n.conversationsRowSemantics(item.peerDisplayName ?? item.peerHandle),
                  titleIcon: item.type == ConversationType.group ? Icons.group_rounded : null,
                  titleIconLabel: l10n.conversationsGroupMark,
                  expiryLabel: conversationExpiryLabel(l10n, item, controller),
                  onTap: () => view.onSelectConversation(item.id),
                ),
              ),
          if (hasSearchQuery) ...messageSearchResultSection(context, view),
        ],
      ),
    );
  }
}

/// The relay's state, the number of conversations and the standing reminder
/// that nothing is backed up, on one line.
class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.connected, required this.refreshing, required this.conversationCount});

  final bool connected;
  final bool refreshing;
  final int conversationCount;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.veilPalette;
    final relay = connected ? l10n.conversationsRelayLinked : l10n.conversationsRelayIdle;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: VeilSpace.xxs),
      child: Row(
        children: [
          if (refreshing)
            SizedBox(
              width: 8,
              height: 8,
              child: CircularProgressIndicator(strokeWidth: 1.5, color: palette.textMuted),
            )
          else
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: connected ? palette.success : palette.warning,
              ),
            ),
          const SizedBox(width: VeilSpace.xs),
          Expanded(
            child: Text(
              '$relay  ·  ${l10n.conversationsCount(conversationCount)}  ·  ${l10n.conversationsNoBackup}',
              // Wraps before it would cut "No backup" off.
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: palette.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.hasQuery});

  final TextEditingController controller;
  final bool hasQuery;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return TextField(
      controller: controller,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        contentPadding: const EdgeInsets.symmetric(horizontal: VeilSpace.md, vertical: VeilSpace.sm + 2),
        prefixIcon: const Icon(Icons.search_rounded),
        hintText: l10n.conversationsSearchHintCompact,
        suffixIcon: !hasQuery
            ? null
            : IconButton(
                tooltip: l10n.chatSearchClearTooltip,
                style: IconButton.styleFrom(backgroundColor: Colors.transparent),
                onPressed: controller.clear,
                icon: const Icon(Icons.close_rounded),
              ),
      ),
    );
  }
}
