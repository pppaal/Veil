import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/app_state.dart';
import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_shell.dart';
import '../../../shared/presentation/veil_ui.dart';
import '../../chat/presentation/chat_room_screen.dart';
import '../data/conversation_models.dart';
import 'conversation_list_logic.dart';
import 'conversation_list_pane.dart';
import 'conversation_list_parts.dart';
import 'conversation_list_phone.dart';

// These were declared here before the screen was split up.
export 'conversation_list_logic.dart';

class ConversationListScreen extends ConsumerStatefulWidget {
  const ConversationListScreen({super.key});

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
  MessageSearchSenderFilter _senderFilter = MessageSearchSenderFilter.all;
  MessageSearchTypeFilter _typeFilter = MessageSearchTypeFilter.all;
  MessageSearchDateFilter _dateFilter = MessageSearchDateFilter.any;
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
    _senderFilter = restored.senderFilter;
    _typeFilter = restored.typeFilter;
    _dateFilter = restored.dateFilter;
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWideLayout = shouldUseWideConversationLayout(constraints.maxWidth);
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
          senderFilter: _senderFilter,
          typeFilter: _typeFilter,
          dateFilter: _dateFilter,
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
          onSenderFilterChanged: (value) {
            setState(() => _senderFilter = value);
            _persistUiState();
            unawaited(_runArchiveSearch());
          },
          onTypeFilterChanged: (value) {
            setState(() => _typeFilter = value);
            _persistUiState();
            unawaited(_runArchiveSearch());
          },
          onDateFilterChanged: (value) {
            setState(() => _dateFilter = value);
            _persistUiState();
            unawaited(_runArchiveSearch());
          },
        );

        final l10n = AppLocalizations.of(context);
        final shellActions = [
          IconButton(
            tooltip: l10n.settingsSecurityStatusTitle,
            onPressed: () => context.push('/security-status'),
            icon: const Icon(Icons.verified_user_outlined),
          ),
          IconButton(
            tooltip: l10n.settingsTitle,
            onPressed: () => context.push('/settings'),
            icon: const Icon(Icons.tune),
          ),
        ];

        // A phone shows the conversations first: starting one moves from the
        // end of the list into the bar.
        if (!isWideLayout) {
          return VeilShell(
            title: 'VEIL',
            padding: EdgeInsets.zero,
            actions: [const _NewConversationButton(), ...shellActions],
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

        return VeilShell(
          title: 'VEIL',
          actions: shellActions,
          maxWidth: null,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Flexible(
                flex: 8,
                child: ConversationListPane(view: view),
              ),
              const SizedBox(width: VeilSpace.lg),
              Expanded(
                flex: 10,
                child: selectedConversation == null
                    ? VeilEmptyState(
                        title: l10n.conversationsChoosePaneTitle,
                        body: l10n.conversationsChoosePaneBody,
                        icon: Icons.forum_outlined,
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          VeilHeroPanel(
                            eyebrow: l10n.conversationsActiveEyebrow,
                            title: selectedConversation.peerDisplayName ??
                                '@${selectedConversation.peerHandle}',
                            body: l10n.conversationsActiveBody,
                            bottom: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                VeilStatusPill(label: l10n.chatPillLocalSearchOnly),
                                VeilStatusPill(label: l10n.conversationsPillOpaqueRelay),
                              ],
                            ),
                          ),
                          const SizedBox(height: VeilSpace.md),
                          Expanded(
                            child: ChatRoomScreen(
                              conversationId: selectedConversation.id,
                              embedded: true,
                              navigationTarget: selectedConversation.id == _selectedConversationId
                                  ? _selectedNavigationTarget
                                  : null,
                            ),
                          ),
                        ],
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
          senderFilter: _senderFilter,
          typeFilter: _typeFilter,
          dateFilter: _dateFilter,
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

    final senderFilter = _senderFilter;
    final typeFilter = _typeFilter;
    final dateFilter = _dateFilter;
    final requestId = ++_archiveSearchRequestId;
    if (mounted) {
      setState(() => _searchingArchive = true);
    }

    final page = await ref.read(messengerControllerProvider).searchMessageArchive(
          query: MessageSearchQuery(
            query: query,
            senderFilter: senderFilter,
            typeFilter: typeFilter,
            dateFilter: dateFilter,
          ),
        );

    if (!mounted ||
        requestId != _archiveSearchRequestId ||
        _searchController.text.trim() != query ||
        senderFilter != _senderFilter ||
        typeFilter != _typeFilter ||
        dateFilter != _dateFilter) {
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

    final senderFilter = _senderFilter;
    final typeFilter = _typeFilter;
    final dateFilter = _dateFilter;
    final requestId = ++_archiveSearchRequestId;
    setState(() => _searchingArchive = true);

    final page = await ref.read(messengerControllerProvider).searchMessageArchive(
          query: MessageSearchQuery(
            query: query,
            senderFilter: senderFilter,
            typeFilter: typeFilter,
            dateFilter: dateFilter,
            beforeSentAt: beforeSentAt,
            beforeMessageId: beforeMessageId,
          ),
        );

    if (!mounted ||
        requestId != _archiveSearchRequestId ||
        _searchController.text.trim() != query ||
        senderFilter != _senderFilter ||
        typeFilter != _typeFilter ||
        dateFilter != _dateFilter) {
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

/// Starts a conversation from the phone list's bar: a 1:1 by handle, or a
/// group.
class _NewConversationButton extends StatelessWidget {
  const _NewConversationButton();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.veilPalette;
    return PopupMenuButton<String>(
      tooltip: l10n.conversationsNewTooltip,
      position: PopupMenuPosition.under,
      color: palette.surfaceRaised,
      onSelected: (route) => context.push(route),
      itemBuilder: (context) => [
        PopupMenuItem(
          value: '/start-chat',
          child: _NewConversationItem(icon: Icons.add_comment_outlined, label: l10n.conversationsNewChat),
        ),
        PopupMenuItem(
          value: '/start-group',
          child: _NewConversationItem(icon: Icons.group_add_outlined, label: l10n.conversationsNewGroup),
        ),
      ],
      icon: const Icon(Icons.edit_square),
    );
  }
}

class _NewConversationItem extends StatelessWidget {
  const _NewConversationItem({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: VeilIconSize.md),
        const SizedBox(width: VeilSpace.sm),
        Text(label, style: Theme.of(context).textTheme.titleSmall),
      ],
    );
  }
}
