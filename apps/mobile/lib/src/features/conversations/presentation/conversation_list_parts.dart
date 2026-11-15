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
      showCheckmark: false,
      selected: value == groupValue,
      onSelected: (_) => onSelected(value),
    );
  }
}

/// The heading of a part of the list while searching ("Chats",
/// "Messages"): small muted type at the text edge, with [trailing] (a
/// spinner) at the end.
class ConversationListHeader extends StatelessWidget {
  const ConversationListHeader({super.key, required this.label, this.trailing});

  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(VeilSpace.md, VeilSpace.md, VeilSpace.md, 6),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: context.veilPalette.textMuted),
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// One message the local search found: a 60 px row with the avatar of the
/// chat it is in, the chat's name and the day it was sent, and the message
/// with the query in the text colour.
class MessageSearchResultTile extends StatelessWidget {
  const MessageSearchResultTile({
    super.key,
    required this.result,
    required this.query,
    required this.timeFormat,
    required this.onTap,
  });

  /// Where the hairline under the row starts: the text edge.
  static const double textInset = VeilSpace.md + 40 + VeilSpace.sm;

  final MessageSearchResult result;
  final String query;
  final DateFormat timeFormat;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final palette = context.veilPalette;
    final snippetStyle = theme.textTheme.bodySmall?.copyWith(color: palette.textMuted);
    return Semantics(
      button: true,
      // Who sent it and what it is, for a screen reader: "You · Text".
      label: messageResultOrigin(l10n, result),
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 60),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: VeilSpace.md, vertical: VeilSpace.xs),
            child: Row(
              children: [
                VeilAvatar(name: result.title, seed: result.peerHandle, size: 40),
                const SizedBox(width: VeilSpace.sm),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              result.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium,
                            ),
                          ),
                          const SizedBox(width: VeilSpace.xs),
                          Text(
                            messageDateLabel(result.sentAt, timeFormat, l10n.localeName),
                            style: theme.textTheme.bodySmall?.copyWith(color: palette.textMuted),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      // The snippet is a person's words: drawn as they wrote
                      // them, with the query in the text colour.
                      RichText(
                        text: TextSpan(
                          style: snippetStyle,
                          children: buildSearchHighlightTextSpans(
                            text: result.bodySnippet,
                            query: query,
                            highlightStyle: snippetStyle?.copyWith(color: palette.text, fontWeight: FontWeight.w600),
                            baseStyle: snippetStyle,
                          ),
                        ),
                        textScaler: MediaQuery.textScalerOf(context),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The messages the local search found under the chats it matched: their
/// heading, the results or a line saying there are none, and the button
/// that loads more.
List<Widget> messageSearchResultSection(BuildContext context, ConversationListView view) {
  final l10n = AppLocalizations.of(context);
  final results = view.archiveResults;
  return [
    ConversationListHeader(
      label: l10n.conversationsMessagesSection,
      trailing: view.searchingArchive
          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
          : null,
    ),
    if (!view.searchingArchive && results.isEmpty)
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: VeilSpace.md),
        child: Text(
          l10n.conversationsNoMessageMatchBody,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: context.veilPalette.textMuted),
        ),
      )
    else ...[
      VeilGroup(
        inset: MessageSearchResultTile.textInset,
        children: [
          for (final result in results)
            RepaintBoundary(
              child: MessageSearchResultTile(
                result: result,
                query: view.searchController.text,
                timeFormat: view.timeFormat,
                onTap: () => view.onSelectMessageResult(result),
              ),
            ),
        ],
      ),
      if (view.archiveHasMore)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: VeilSpace.xs),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: VeilButton(
              expanded: false,
              onPressed: view.searchingArchive ? null : view.onLoadMoreMessageResults,
              tone: VeilButtonTone.ghost,
              label: view.searchingArchive ? l10n.conversationsLoadingMore : l10n.conversationsLoadMore,
            ),
          ),
        ),
    ],
  ];
}
