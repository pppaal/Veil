import 'package:flutter/material.dart';

import '../../../app/app_state.dart';
import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_ui.dart';
import '../../chat/presentation/message_time.dart';
import '../data/conversation_models.dart';
import '../data/veil_messenger_controller.dart';
import 'conversation_list_labels.dart';
import 'conversation_list_logic.dart';
import 'peer_names.dart';

/// What a layout of the conversation list shows and what it can ask for:
/// the same for the wide pane and the phone list, which differ only in how
/// they lay it out.
class ConversationListView {
  const ConversationListView({
    required this.session,
    required this.controller,
    required this.names,
    required this.conversations,
    required this.archiveResults,
    required this.searchingArchive,
    required this.archiveHasMore,
    required this.searchController,
    required this.timeFormat,
    required this.now,
    required this.selectedConversationId,
    required this.onSelectConversation,
    required this.onSelectMessageResult,
    required this.onLoadMoreMessageResults,
  });

  final AppSessionState session;
  final VeilMessengerController controller;

  /// What the rows call people: the nicknames on this phone.
  final PeerNames names;

  /// The conversations to list: all of them, or those the query matches.
  final List<ConversationPreview> conversations;
  final List<MessageSearchResult> archiveResults;
  final bool searchingArchive;
  final bool archiveHasMore;
  final TextEditingController searchController;

  /// How the rows say when their last message was sent, seen on [now].
  final MessageTimeFormat timeFormat;
  final DateTime now;
  final String? selectedConversationId;
  final ValueChanged<String> onSelectConversation;
  final ValueChanged<MessageSearchResult> onSelectMessageResult;
  final VoidCallback onLoadMoreMessageResults;

  bool get hasSearchQuery => searchController.text.trim().isNotEmpty;
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
/// chat it is in, the chat's name in bold and the day it was sent, and the
/// message with the query in bold. The avatar and the name are the ones the
/// chat's own row shows: a group's neutral disc and its name, never the
/// letter or the name of the member the search result happens to carry.
class MessageSearchResultTile extends StatelessWidget {
  const MessageSearchResultTile({
    super.key,
    required this.result,
    required this.query,
    required this.timeFormat,
    required this.now,
    required this.onTap,
    required this.names,
    this.conversation,
    this.localUserId,
  });

  /// Where the hairline under the row starts: the text edge.
  static const double textInset = VeilSpace.md + 40 + VeilSpace.sm;

  final MessageSearchResult result;
  final String query;
  final MessageTimeFormat timeFormat;
  final DateTime now;
  final VoidCallback onTap;

  /// What the hit's chat is called by: the nicknames on this phone.
  final PeerNames names;

  /// The chat the message is in, when this device still lists it.
  final ConversationPreview? conversation;

  /// The user's own id, which a group named after its members leaves out.
  final String? localUserId;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final palette = context.veilPalette;
    final snippetStyle = theme.textTheme.bodySmall?.copyWith(color: palette.textMuted);
    final chat = conversation;
    final group = chat?.type == ConversationType.group;
    final title = chat == null
        ? names.nicknameOf(result.peerHandle) ?? '@${result.peerHandle}'
        : conversationRowTitle(l10n, chat, names, localUserId: localUserId);
    return Semantics(
      button: true,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 60),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: VeilSpace.md, vertical: VeilSpace.xs),
            child: Row(
              children: [
                // Seeded as the chat's row is: a group has no handle of its own.
                VeilAvatar(name: title, seed: group ? chat!.id : result.peerHandle, size: 40, group: group),
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
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                            ),
                          ),
                          const SizedBox(width: VeilSpace.xs),
                          Text(
                            timeFormat.listDate(result.sentAt, now: now),
                            style: theme.textTheme.bodySmall?.copyWith(color: palette.textMuted),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      // The snippet is a person's words: drawn as they wrote
                      // them, with the query in bold, and led by "You: " when
                      // they are the user's own, in a 1:1 too. That departs
                      // from the pattern sheet (M8: hits carry no You/Them
                      // label, as Signal's): a hit stands apart from its chat,
                      // and nothing else on it says whose words they are. A
                      // group's row leads its own last message the same way.
                      RichText(
                        text: TextSpan(
                          style: snippetStyle,
                          children: [
                            if (result.isMine) TextSpan(text: l10n.conversationsPreviewYou('')),
                            ...buildSearchHighlightTextSpans(
                              text: result.bodySnippet,
                              query: query,
                              highlightStyle: snippetStyle?.copyWith(color: palette.text, fontWeight: FontWeight.w600),
                              baseStyle: snippetStyle,
                            ),
                          ],
                        ),
                        textScaler: MediaQuery.textScalerOf(context),
                        maxLines: 1,
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
/// heading, the results and the button that loads more. Nothing while no
/// message matched.
List<Widget> messageSearchResultSection(BuildContext context, ConversationListView view) {
  final l10n = AppLocalizations.of(context);
  final results = view.archiveResults;
  if (results.isEmpty) return const [];
  return [
    ConversationListHeader(
      label: l10n.conversationsMessagesSection,
      trailing: view.searchingArchive
          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
          : null,
    ),
    ...[
      VeilGroup(
        inset: MessageSearchResultTile.textInset,
        children: [
          for (final result in results)
            RepaintBoundary(
              child: MessageSearchResultTile(
                result: result,
                conversation: view.controller.conversationById(result.conversationId),
                names: view.names,
                localUserId: view.session.userId,
                query: view.searchController.text,
                timeFormat: view.timeFormat,
                now: view.now,
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
