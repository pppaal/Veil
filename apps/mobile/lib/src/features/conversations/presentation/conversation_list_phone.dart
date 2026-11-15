import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_error_text.dart';
import '../../../shared/presentation/veil_ui.dart';
import '../data/conversation_models.dart';
import 'conversation_list_labels.dart';
import 'conversation_list_logic.dart';
import 'conversation_list_parts.dart';

/// The conversation list, content first: one line of status (the relay, how
/// many conversations, no backup), the search field, then the
/// conversations. Search filters and the messages a search found appear
/// only while a query is typed, and a sync error only while there is one.
///
/// A phone shows it as the screen. The wide layout shows the same list as
/// its first pane, with the open conversation's row marked.
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
    final loadingFirstList = conversations.isEmpty && controller.isBusy && !hasSearchQuery;
    final localUserId = view.session.userId;
    final error = controller.errorMessage;

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
            conversationCount: loadingFirstList ? null : controller.conversations.length,
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
          if (error != null) ...[
            const SizedBox(height: VeilSpace.xs),
            // The dropped relay link is a wait, not a failure: what is
            // queued goes out by itself once the link is back.
            if (controller.errorIsRelayInterruption)
              VeilInlineBanner(
                dense: true,
                title: l10n.chatBannerRelayReconnecting,
                message: l10n.conversationsRelayInterruptedBody,
                tone: VeilBannerTone.warn,
                icon: Icons.sync_problem_rounded,
              )
            else
              VeilInlineBanner(
                dense: true,
                title: l10n.conversationsSyncIssueTitle,
                message: veilErrorText(l10n, error),
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
                  selected: item.id == view.selectedConversationId,
                  title: conversationRowTitle(l10n, item, localUserId: localUserId),
                  // What the avatar's colour is drawn from: a group has no
                  // handle of its own.
                  handle: item.type == ConversationType.group ? item.id : item.peerHandle,
                  subtitle: conversationPreviewLine(l10n, item, controller),
                  timestamp: view.timeFormat.format(item.updatedAt),
                  semanticLabel: conversationRowSemantics(l10n, item, localUserId: localUserId),
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
/// that nothing is backed up, on one line where it fits. Where it does not
/// (larger text, a narrow screen) the line breaks between two parts, and
/// the dot that separates parts is drawn only between two that share a
/// line: no line ends or starts with one.
class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.connected, required this.refreshing, required this.conversationCount});

  static const _separator = '  ·  ';

  final bool connected;
  final bool refreshing;

  /// How many conversations there are; null while the first list is still
  /// on its way and nobody knows.
  final int? conversationCount;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.veilPalette;
    final relay = connected ? l10n.conversationsRelayLinked : l10n.conversationsRelayIdle;
    final parts = [
      relay,
      if (conversationCount case final count?) l10n.conversationsCount(count),
      l10n.conversationsNoBackup,
    ];
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(color: palette.textMuted);
    final textScaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);

    double widthOf(String text) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: direction,
        textScaler: textScaler,
        maxLines: 1,
      )..layout();
      final width = painter.width;
      painter.dispose();
      return width;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: VeilSpace.xxs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            // Beside the first line, whatever the text size.
            padding: EdgeInsets.only(top: textScaler.scale((style?.fontSize ?? 12) * (style?.height ?? 1.4)) / 2 - 4),
            child: refreshing
                ? SizedBox(
                    width: 8,
                    height: 8,
                    child: CircularProgressIndicator(strokeWidth: 1.5, color: palette.textMuted),
                  )
                : Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: connected ? palette.success : palette.warning,
                    ),
                  ),
          ),
          const SizedBox(width: VeilSpace.xs),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final lines = packPartsIntoLines(
                  [for (final part in parts) widthOf(part)],
                  separatorWidth: widthOf(_separator),
                  maxWidth: constraints.maxWidth,
                );
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final line in lines)
                      Text(
                        [for (final index in line) parts[index]].join(_separator),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: style,
                      ),
                  ],
                );
              },
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
