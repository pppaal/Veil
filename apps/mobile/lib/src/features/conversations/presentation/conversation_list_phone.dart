import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_ui.dart';
import '../../safety/data/safety_providers.dart';
import '../data/conversation_models.dart';
import '../data/veil_messenger_controller.dart';
import 'conversation_list_labels.dart';
import 'conversation_list_parts.dart';
import 'conversation_row.dart';
import 'group_last_sender.dart';

/// The Chats list, content first: the search field, then the chats as
/// full-bleed rows. While a query is typed the rows are the chats and the
/// messages it matched, each under its heading, and a part with no match is
/// left out. A failed refresh is one line with Retry, only while it holds.
/// The connection state is the bar's title (see ConversationListScreen);
/// while the first list is on its way nothing is shown under the field.
///
/// A phone shows it as the screen. The wide layout shows the same list as
/// its first pane, with the open conversation's row marked.
class ConversationListPhone extends ConsumerWidget {
  const ConversationListPhone({super.key, required this.view});

  final ConversationListView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final mutes = ref.watch(conversationMutesProvider);
    final controller = view.controller;
    final conversations = view.conversations;
    final hasSearchQuery = view.hasSearchQuery;
    final loadingFirstList = conversations.isEmpty && controller.isBusy && !hasSearchQuery;
    final localUserId = view.session.userId;
    final error = controller.errorMessage;
    final noResults = hasSearchQuery && conversations.isEmpty && view.archiveResults.isEmpty && !view.searchingArchive;
    // A narrow phone gets the 64 px row.
    final dense = MediaQuery.sizeOf(context).width < 380;

    return LayoutBuilder(
      builder: (context, constraints) => RefreshIndicator(
        color: context.veilPalette.primaryStrong,
        onRefresh: controller.refreshConversations,
        child: ListView(
          key: const PageStorageKey<String>('conversation-list-scroll'),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.only(bottom: VeilSpace.md),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(VeilSpace.md, VeilSpace.xs, VeilSpace.md, VeilSpace.xs),
              child: _SearchField(controller: view.searchController, hasQuery: hasSearchQuery),
            ),
            // A dropped link to the server is the bar's "Connecting…", not a
            // failure: what is queued goes out by itself once it is back.
            if (error != null && !controller.errorIsRelayInterruption)
              _SyncFailedLine(onRetry: controller.refreshConversations),
            if (hasSearchQuery && conversations.isNotEmpty) ConversationListHeader(label: l10n.conversationsSectionLabel),
            if (loadingFirstList)
              const SizedBox.shrink()
            else if (noResults)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: VeilSpace.md, vertical: VeilSpace.xxl),
                child: Text(
                  l10n.conversationsNoMatchTitle(view.searchController.text.trim()),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: context.veilPalette.textMuted),
                ),
              )
            else if (conversations.isEmpty && hasSearchQuery)
              const SizedBox.shrink()
            else if (conversations.isEmpty)
              // In the middle of the space under the field, a little above
              // its centre. That space is a floor, not a height: when the
              // keyboard is up or the phone is on its side the state is
              // taller than it, and the list scrolls to the button.
              ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: ((constraints.maxHeight - _searchRowExtent) * 0.8).clamp(0, double.infinity),
                ),
                child: VeilEmptyState(
                  title: l10n.conversationsNoneYetTitle,
                  action: VeilButton(
                    expanded: false,
                    onPressed: () => context.push('/start-chat'),
                    label: l10n.conversationsStartDirect,
                    tone: VeilButtonTone.secondary,
                  ),
                ),
              )
            else
              VeilGroup(
                inset: ConversationRow.textInset,
                children: [
                  for (final item in conversations)
                    RepaintBoundary(
                      child: ConversationRow(
                        dense: dense,
                        selected: item.id == view.selectedConversationId,
                        title: conversationRowTitle(l10n, item, localUserId: localUserId),
                        // What the avatar's colour is drawn from: a group has
                        // no handle of its own.
                        seed: item.type == ConversationType.group ? item.id : item.peerHandle,
                        group: item.type == ConversationType.group,
                        snippet: conversationPreviewLine(
                          l10n,
                          item,
                          controller,
                          groupSender: _groupSender(ref, item, controller),
                        ),
                        // A chat with no message yet has no time to show.
                        timestamp: item.lastEnvelope == null ? '' : view.timeFormat.listDate(item.updatedAt, now: view.now),
                        semanticLabel: conversationRowSemantics(l10n, item, localUserId: localUserId),
                        unreadCount: item.unreadCount,
                        unreadLabel: item.unreadCount > 0 ? l10n.conversationsUnreadSemantics(item.unreadCount) : null,
                        timerLabel: conversationTimerLabel(l10n, item, controller),
                        muted: mutes.isMuted(item.id),
                        mutedLabel: l10n.conversationsMutedSemantics,
                        onTap: () => view.onSelectConversation(item.id),
                      ),
                    ),
                ],
              ),
            if (hasSearchQuery) ...messageSearchResultSection(context, view),
          ],
        ),
      ),
    );
  }

  /// The height of the search field's row above the chats.
  static const double _searchRowExtent = 60;

  // Who wrote a group's last message, when someone else did.
  static String? _groupSender(WidgetRef ref, ConversationPreview item, VeilMessengerController controller) {
    if (item.type != ConversationType.group) return null;
    final last = controller.messagesFor(item.id).lastOrNull;
    if (last == null || last.isMine || last.isLocalNotice) return null;
    return ref.watch(groupLastSenderProvider((conversationId: item.id, deviceId: last.senderDeviceId))).valueOrNull;
  }
}

/// A refresh of the list that failed: one line under the search field, and
/// Retry at its end.
class _SyncFailedLine extends StatelessWidget {
  const _SyncFailedLine({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: VeilSpace.md, end: VeilSpace.xxs),
      child: Row(
        children: [
          Expanded(
            child: Text(
              l10n.conversationsSyncIssueTitle,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: context.veilPalette.textMuted),
            ),
          ),
          VeilButton(expanded: false, tone: VeilButtonTone.ghost, label: l10n.commonRetry, onPressed: onRetry),
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
    final palette = context.veilPalette;
    return TextField(
      controller: controller,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        isDense: true,
        prefixIcon: Icon(Icons.search, color: palette.textMuted),
        prefixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 44),
        hintText: l10n.conversationsSearchHintCompact,
        suffixIconConstraints: const BoxConstraints(minWidth: 44, minHeight: 44),
        // 44 square like the field, so the field keeps its height when the
        // button appears on the first character.
        suffixIcon: !hasQuery
            ? null
            : IconButton(
                tooltip: l10n.chatSearchClearTooltip,
                onPressed: controller.clear,
                style: IconButton.styleFrom(
                  minimumSize: const Size.square(44),
                  maximumSize: const Size.square(44),
                  padding: EdgeInsets.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                icon: const Icon(Icons.close, size: 20),
              ),
      ),
    );
  }
}
