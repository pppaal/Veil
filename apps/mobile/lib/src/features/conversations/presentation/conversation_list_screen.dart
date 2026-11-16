import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/app_state.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_shell.dart';
import '../../../shared/presentation/veil_ui.dart';
import '../../chat/presentation/chat_bar.dart';
import '../../chat/presentation/chat_room_screen.dart';
import '../data/conversation_models.dart';
import 'conversation_list_logic.dart';
import 'conversation_list_parts.dart';
import 'conversation_list_phone.dart';

// These were declared here before the screen was split up.
export 'conversation_list_logic.dart';

/// The conversations. On a phone the list is the screen and a chat opens on
/// top of it. From 1120 px (shouldUseWideConversationLayout) the same list
/// keeps the open chat beside it: two panes, each under its own bar, with
/// nothing above the rows or the messages that a phone does not show.
class ConversationListScreen extends ConsumerStatefulWidget {
  const ConversationListScreen({super.key});

  /// How wide the list's pane is in the wide layout.
  static const double listPaneWidth = 380;

  @override
  ConsumerState<ConversationListScreen> createState() => _ConversationListScreenState();
}

class _ConversationListScreenState extends ConsumerState<ConversationListScreen> {
  final _timeFormat = DateFormat('HH:mm');
  final _searchController = TextEditingController();
  Timer? _archiveSearchDebounce;
  int _archiveSearchRequestId = 0;
  String? _selectedConversationId;
  MessageNavigationTarget? _selectedNavigationTarget;
  int _navigationRequestCounter = 0;
  List<MessageSearchResult> _archiveResults = const <MessageSearchResult>[];
  bool _searchingArchive = false;
  DateTime? _archiveNextBeforeSentAt;
  String? _archiveNextBeforeMessageId;
  bool _restoredUiState = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_handleSearchChanged);
    scheduleMicrotask(() async {
      await ref.read(messengerControllerProvider).refreshConversations();
      await _runArchiveSearch();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_restoredUiState) {
      return;
    }
    _restoredUiState = true;
    final restored = decodeConversationListViewState(
      PageStorage.maybeOf(context)?.readState(
        context,
        identifier: _conversationListViewStateStorageKey,
      ),
    );
    if (restored == null) {
      return;
    }
    _searchController.text = restored.query;
    _selectedConversationId = restored.selectedConversationId;
    _navigationRequestCounter = restored.lastNavigationRequestId;
  }

  @override
  void dispose() {
    _searchController.removeListener(_handleSearchChanged);
    _archiveSearchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _handleSearchChanged() {
    setState(() {});
    _persistUiState();
    _archiveSearchDebounce?.cancel();
    _archiveSearchDebounce = Timer(
      const Duration(milliseconds: 180),
      () => unawaited(_runArchiveSearch()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(appSessionProvider);
    final controller = ref.watch(messengerControllerProvider);
    final conversations = controller.conversations;
    final filteredConversations = _filterConversations(conversations);

    return Builder(
      builder: (context) {
        // The window's width, not this screen's: from 1024 the tabs are a
        // rail beside it, and a new chat (StartDirectChatScreen) decides on
        // the window too whether it opens beside the list.
        final isWideLayout = shouldUseWideConversationLayout(MediaQuery.sizeOf(context).width);
        if (isWideLayout &&
            _selectedConversationId == null &&
            filteredConversations.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _selectedConversationId == null) {
              setState(() => _selectedConversationId = filteredConversations.first.id);
              _persistUiState();
            }
          });
        }

        final view = ConversationListView(
          session: session,
          controller: controller,
          conversations: filteredConversations,
          archiveResults: _archiveResults,
          searchingArchive: _searchingArchive,
          archiveHasMore:
              _archiveNextBeforeSentAt != null && _archiveNextBeforeMessageId != null,
          searchController: _searchController,
          timeFormat: _timeFormat,
          selectedConversationId: isWideLayout ? _selectedConversationId : null,
          onSelectConversation: (conversationId) {
            if (isWideLayout) {
              setState(() {
                _selectedConversationId = conversationId;
                _selectedNavigationTarget = null;
              });
              _persistUiState();
              return;
            }
            context.push('/chat/$conversationId');
          },
          onSelectMessageResult: (result) {
            final target = _issueNavigationTarget(result.messageId);
            if (isWideLayout) {
              setState(() {
                _selectedConversationId = result.conversationId;
                _selectedNavigationTarget = target;
              });
              _persistUiState();
              return;
            }
            context.push('/chat/${result.conversationId}', extra: target);
          },
          onLoadMoreMessageResults: () => unawaited(_loadMoreArchiveResults()),
        );

        final l10n = AppLocalizations.of(context);
        // Starting a chat is the bar's one action.
        const barActions = [_NewConversationButton()];
        // While there is no connection the bar's title says so in place of
        // "Chats".
        final title = controller.realtimeConnected
            ? l10n.navChats
            : controller.errorIsRelayInterruption
                ? l10n.conversationsBarOffline
                : l10n.conversationsBarConnecting;

        if (!isWideLayout) {
          return VeilShell(
            title: title,
            actions: barActions,
            child: ConversationListPhone(view: view),
          );
        }

        ConversationPreview? selectedConversation;
        for (final conversation in filteredConversations) {
          if (conversation.id == _selectedConversationId) {
            selectedConversation = conversation;
            break;
          }
        }
        selectedConversation ??= conversations.cast<ConversationPreview?>().firstWhere(
              (conversation) => conversation?.id == _selectedConversationId,
              orElse: () => null,
            );
        selectedConversation ??=
            filteredConversations.isEmpty ? null : filteredConversations.first;

        final palette = context.veilPalette;
        return VeilShell(
          maxWidth: null,
          padding: EdgeInsets.zero,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: ConversationListScreen.listPaneWidth,
                child: Column(
                  children: [
                    ChatPaneBar(title: title, actions: barActions),
                    Expanded(child: ConversationListPhone(view: view)),
                  ],
                ),
              ),
              Container(width: 0.5, color: palette.stroke),
              Expanded(
                // With no chat open the pane says one muted line, also when
                // there is no chat at all: the list beside it has the empty
                // state and its button.
                child: selectedConversation == null
                    ? Center(
                        child: Text(
                          l10n.conversationsChoosePaneTitle,
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: palette.textMuted),
                        ),
                      )
                    : ChatRoomScreen(
                        conversationId: selectedConversation.id,
                        embedded: true,
                        navigationTarget:
                            selectedConversation.id == _selectedConversationId ? _selectedNavigationTarget : null,
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  List<ConversationPreview> _filterConversations(List<ConversationPreview> conversations) {
    return filterConversationPreviews(conversations, _searchController.text);
  }

  MessageNavigationTarget _issueNavigationTarget(String messageId) {
    _navigationRequestCounter += 1;
    final target = issueMessageNavigationTarget(
      messageId: messageId,
      requestId: _navigationRequestCounter,
      query: _searchController.text,
    );
    _persistUiState();
    return target;
  }

  void _persistUiState() {
    PageStorage.maybeOf(context)?.writeState(
      context,
      encodeConversationListViewState(
        ConversationListViewState(
          query: _searchController.text,
          selectedConversationId: _selectedConversationId,
          lastNavigationRequestId: _navigationRequestCounter,
        ),
      ),
      identifier: _conversationListViewStateStorageKey,
    );
  }

  Future<void> _runArchiveSearch() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      if (!mounted) {
        return;
      }
      _archiveSearchRequestId += 1;
      setState(() {
        _archiveResults = const <MessageSearchResult>[];
        _searchingArchive = false;
        _archiveNextBeforeSentAt = null;
        _archiveNextBeforeMessageId = null;
      });
      return;
    }

    final requestId = ++_archiveSearchRequestId;
    if (mounted) {
      setState(() => _searchingArchive = true);
    }

    final page = await ref.read(messengerControllerProvider).searchMessageArchive(
          query: MessageSearchQuery(query: query),
        );

    if (!mounted ||
        requestId != _archiveSearchRequestId ||
        _searchController.text.trim() != query) {
      return;
    }

    setState(() {
      _archiveResults = page.items;
      _searchingArchive = false;
      _archiveNextBeforeSentAt = page.nextBeforeSentAt;
      _archiveNextBeforeMessageId = page.nextBeforeMessageId;
    });
  }

  Future<void> _loadMoreArchiveResults() async {
    final query = _searchController.text.trim();
    final beforeSentAt = _archiveNextBeforeSentAt;
    final beforeMessageId = _archiveNextBeforeMessageId;
    if (query.isEmpty || beforeSentAt == null || beforeMessageId == null || _searchingArchive) {
      return;
    }

    final requestId = ++_archiveSearchRequestId;
    setState(() => _searchingArchive = true);

    final page = await ref.read(messengerControllerProvider).searchMessageArchive(
          query: MessageSearchQuery(
            query: query,
            beforeSentAt: beforeSentAt,
            beforeMessageId: beforeMessageId,
          ),
        );

    if (!mounted ||
        requestId != _archiveSearchRequestId ||
        _searchController.text.trim() != query) {
      return;
    }

    setState(() {
      _archiveResults = mergeArchiveSearchResults(_archiveResults, page.items);
      _searchingArchive = false;
      _archiveNextBeforeSentAt = page.nextBeforeSentAt;
      _archiveNextBeforeMessageId = page.nextBeforeMessageId;
    });
  }
}

const String _conversationListViewStateStorageKey = 'conversation-list-view-state';

/// Starts a chat from the Chats bar: the New chat screen, where "New group"
/// is the first row.
class _NewConversationButton extends StatelessWidget {
  const _NewConversationButton();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return IconButton(
      tooltip: l10n.conversationsNewTooltip,
      onPressed: () => context.push('/start-chat'),
      icon: const Icon(Icons.edit_outlined),
    );
  }
}
