import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app/app_state.dart';
import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_ui.dart';
import '../data/conversation_models.dart';
import '../data/veil_messenger_controller.dart';
import 'conversation_list_labels.dart';
import 'conversation_list_logic.dart';

/// What a layout of the conversation list shows and what it can ask for:
/// the same for the wide pane and the phone list, which differ only in how
/// they lay it out.
class ConversationListView {
  const ConversationListView({
    required this.session,
    required this.controller,
    required this.conversations,
    required this.archiveResults,
    required this.searchingArchive,
    required this.archiveHasMore,
    required this.searchController,
    required this.senderFilter,
    required this.typeFilter,
    required this.dateFilter,
    required this.timeFormat,
    required this.selectedConversationId,
    required this.onSelectConversation,
    required this.onSelectMessageResult,
    required this.onLoadMoreMessageResults,
    required this.onSenderFilterChanged,
    required this.onTypeFilterChanged,
    required this.onDateFilterChanged,
  });

  final AppSessionState session;
  final VeilMessengerController controller;

  /// The conversations to list: all of them, or those the query matches.
  final List<ConversationPreview> conversations;
  final List<MessageSearchResult> archiveResults;
  final bool searchingArchive;
  final bool archiveHasMore;
  final TextEditingController searchController;
  final MessageSearchSenderFilter senderFilter;
  final MessageSearchTypeFilter typeFilter;
  final MessageSearchDateFilter dateFilter;
  final DateFormat timeFormat;
  final String? selectedConversationId;
  final ValueChanged<String> onSelectConversation;
  final ValueChanged<MessageSearchResult> onSelectMessageResult;
  final VoidCallback onLoadMoreMessageResults;
  final ValueChanged<MessageSearchSenderFilter> onSenderFilterChanged;
  final ValueChanged<MessageSearchTypeFilter> onTypeFilterChanged;
  final ValueChanged<MessageSearchDateFilter> onDateFilterChanged;

  bool get hasSearchQuery => searchController.text.trim().isNotEmpty;
}

/// The sender, type and date filters of the local message search.
List<Widget> conversationSearchFilterChips(AppLocalizations l10n, ConversationListView view) {
  return [
    _SearchChip<MessageSearchSenderFilter>(
      value: MessageSearchSenderFilter.all,
      groupValue: view.senderFilter,
      label: l10n.conversationsFilterAllSenders,
      onSelected: view.onSenderFilterChanged,
    ),
    _SearchChip<MessageSearchSenderFilter>(
      value: MessageSearchSenderFilter.mine,
      groupValue: view.senderFilter,
      label: l10n.conversationsFilterMine,
      onSelected: view.onSenderFilterChanged,
    ),
    _SearchChip<MessageSearchSenderFilter>(
      value: MessageSearchSenderFilter.theirs,
      groupValue: view.senderFilter,
      label: l10n.conversationsFilterTheirs,
      onSelected: view.onSenderFilterChanged,
    ),
    _SearchChip<MessageSearchTypeFilter>(
      value: MessageSearchTypeFilter.all,
      groupValue: view.typeFilter,
      label: l10n.conversationsFilterAllTypes,
      onSelected: view.onTypeFilterChanged,
    ),
    _SearchChip<MessageSearchTypeFilter>(
      value: MessageSearchTypeFilter.text,
      groupValue: view.typeFilter,
      label: l10n.conversationsFilterText,
      onSelected: view.onTypeFilterChanged,
    ),
    _SearchChip<MessageSearchTypeFilter>(
      value: MessageSearchTypeFilter.media,
      groupValue: view.typeFilter,
      label: l10n.conversationsFilterMedia,
      onSelected: view.onTypeFilterChanged,
    ),
    _SearchChip<MessageSearchDateFilter>(
      value: MessageSearchDateFilter.any,
      groupValue: view.dateFilter,
      label: l10n.conversationsFilterAnyDate,
      onSelected: view.onDateFilterChanged,
    ),
    _SearchChip<MessageSearchDateFilter>(
      value: MessageSearchDateFilter.last7Days,
      groupValue: view.dateFilter,
      label: l10n.conversationsFilterLast7Days,
      onSelected: view.onDateFilterChanged,
    ),
    _SearchChip<MessageSearchDateFilter>(
      value: MessageSearchDateFilter.last30Days,
      groupValue: view.dateFilter,
      label: l10n.conversationsFilterLast30Days,
      onSelected: view.onDateFilterChanged,
    ),
  ];
}

class _SearchChip<T> extends StatelessWidget {
  const _SearchChip({
    required this.value,
    required this.groupValue,
    required this.label,
    required this.onSelected,
  });

  final T value;
  final T groupValue;
  final String label;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: value == groupValue,
      onSelected: (_) => onSelected(value),
    );
  }
}

/// The placeholder rows shown while the first list is on its way: the
/// shape of the rows that will take their place, so nothing jumps when they
/// do. A screen reader hears that the list is loading.
class ConversationListSkeleton extends StatelessWidget {
  const ConversationListSkeleton({super.key});

  // How wide the name of each placeholder row is.
  static const _nameWidths = [132.0, 88.0, 164.0, 112.0, 148.0];

  @override
  Widget build(BuildContext context) {
    final palette = context.veilPalette;
    return Semantics(
      label: AppLocalizations.of(context).commonLoading,
      child: ExcludeSemantics(
        child: Column(
          children: [
            for (final nameWidth in _nameWidths)
              Container(
                margin: const EdgeInsets.symmetric(vertical: 2),
                padding: const EdgeInsets.all(VeilSpace.sm),
                decoration: BoxDecoration(
                  color: palette.surface,
                  borderRadius: BorderRadius.circular(VeilRadius.md),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(color: palette.surfaceAlt, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: VeilSpace.sm + 2),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          VeilSkeletonLine(width: nameWidth, height: 14),
                          const SizedBox(height: VeilSpace.xs),
                          const FractionallySizedBox(widthFactor: 0.72, child: VeilSkeletonLine()),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// One message the local search found, with the query marked in its text.
class MessageSearchResultTile extends StatelessWidget {
  const MessageSearchResultTile({
    super.key,
    required this.result,
    required this.query,
    required this.timeFormat,
    required this.onTap,
  });

  final MessageSearchResult result;
  final String query;
  final DateFormat timeFormat;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final palette = context.veilPalette;
    return VeilListTileCard(
      // Who sent it, what it is and when: "You · Text · 09:45".
      eyebrow: '${messageResultOrigin(l10n, result)} · '
          '${messageDateLabel(result.sentAt, timeFormat, l10n.localeName)}',
      leading: Icon(messageKindIcon(result.messageKind)),
      title: result.title,
      subtitle: result.bodySnippet,
      // The snippet is a person's words: drawn as they wrote them, with
      // the query marked.
      subtitleWidget: RichText(
        text: TextSpan(
          style: theme.textTheme.bodyMedium?.copyWith(color: palette.textMuted),
          children: buildSearchHighlightTextSpans(
            text: result.bodySnippet,
            query: query,
            highlightStyle: theme.textTheme.bodyMedium?.copyWith(
              color: palette.text,
              fontWeight: FontWeight.w700,
            ),
            baseStyle: theme.textTheme.bodyMedium?.copyWith(color: palette.textMuted),
          ),
        ),
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: const Icon(Icons.north_east_rounded, size: 18),
      onTap: onTap,
    );
  }
}

/// The messages the local search found under the conversations it matched:
/// their heading with a count, the results or a line saying there are
/// none, and the button that loads more.
List<Widget> messageSearchResultSection(BuildContext context, ConversationListView view) {
  final l10n = AppLocalizations.of(context);
  final results = view.archiveResults;
  return [
    const SizedBox(height: VeilSpace.md),
    VeilSectionLabel(
      l10n.conversationsMessagesSection,
      trailing: view.searchingArchive
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Text(
              l10n.conversationsResultCount(results.length),
              style: Theme.of(context).textTheme.bodySmall,
            ),
    ),
    const SizedBox(height: VeilSpace.sm),
    if (!view.searchingArchive && results.isEmpty)
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: VeilSpace.xxs),
        child: VeilCopy(
          l10n.conversationsNoMessageMatchBody,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: context.veilPalette.textMuted),
        ),
      )
    else ...[
      for (final result in results)
        Padding(
          padding: const EdgeInsets.only(bottom: VeilSpace.sm),
          child: RepaintBoundary(
            child: MessageSearchResultTile(
              result: result,
              query: view.searchController.text,
              timeFormat: view.timeFormat,
              onTap: () => view.onSelectMessageResult(result),
            ),
          ),
        ),
      if (view.archiveHasMore)
        Padding(
          padding: const EdgeInsets.only(top: VeilSpace.xs, bottom: VeilSpace.sm),
          child: Align(
            alignment: Alignment.centerLeft,
            child: VeilButton(
              expanded: false,
              onPressed: view.searchingArchive ? null : view.onLoadMoreMessageResults,
              tone: VeilButtonTone.secondary,
              label: view.searchingArchive ? l10n.conversationsLoadingMore : l10n.conversationsLoadMore,
              icon: Icons.expand_more_rounded,
            ),
          ),
        ),
    ],
  ];
}
