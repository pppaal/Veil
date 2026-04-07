import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/app_state.dart';
import '../../../core/crypto/crypto_engine.dart';
import '../../../core/theme/veil_theme.dart';
import '../../../shared/presentation/veil_shell.dart';
import '../../../shared/presentation/veil_ui.dart';
import '../../chat/presentation/chat_room_screen.dart';
import '../../chat/presentation/message_expiration.dart';
import '../data/conversation_models.dart';
import '../data/veil_messenger_controller.dart';

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

  String _subtitleForConversation(
    ConversationPreview item,
    VeilMessengerController controller,
  ) {
    final pendingCount = controller.pendingCountFor(item.id);
    if (pendingCount > 0) {
      return pendingCount == 1 ? '1 message queued locally' : '$pendingCount messages queued locally';
    }

    final envelope = item.lastEnvelope;
    if (envelope == null) {
      return 'No messages yet';
    }

    if (isMessageExpired(envelope.expiresAt)) {
      return 'Expired locally';
    }

    switch (envelope.messageKind) {
      case MessageKind.image:
        return 'Encrypted image';
      case MessageKind.file:
        return 'Encrypted attachment';
      case MessageKind.system:
        return 'System envelope';
      case MessageKind.text:
        return 'Encrypted message';
    }
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

        final listPane = _ConversationListPane(
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
          subtitleForConversation: _subtitleForConversation,
          timeFormat: _timeFormat,
          selectedConversationId: _selectedConversationId,
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

        if (!isWideLayout) {
          return VeilShell(
            title: 'VEIL',
            actions: [
              IconButton(
                tooltip: 'Security status',
                onPressed: () => context.push('/security-status'),
                icon: const Icon(Icons.verified_user_outlined),
              ),
              IconButton(
                tooltip: 'Settings',
                onPressed: () => context.push('/settings'),
                icon: const Icon(Icons.tune),
              ),
            ],
            child: listPane,
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
          actions: [
            IconButton(
              tooltip: 'Security status',
              onPressed: () => context.push('/security-status'),
              icon: const Icon(Icons.verified_user_outlined),
            ),
            IconButton(
              tooltip: 'Settings',
              onPressed: () => context.push('/settings'),
              icon: const Icon(Icons.tune),
            ),
          ],
          maxWidth: null,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Flexible(
                flex: 8,
                child: listPane,
              ),
              const SizedBox(width: VeilSpace.lg),
              Expanded(
                flex: 10,
                child: selectedConversation == null
                    ? const VeilEmptyState(
                        title: 'Choose a direct conversation',
                        body:
                            'Wide layout keeps your conversation list visible while you read and send locally.',
                        icon: Icons.forum_outlined,
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                          VeilHeroPanel(
                            eyebrow: 'ACTIVE CONVERSATION',
                            title: selectedConversation.peerDisplayName ??
                                '@${selectedConversation.peerHandle}',
                            body:
                                'Adaptive layout keeps conversation context and message flow visible at the same time.',
                            bottom: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: const [
                                VeilStatusPill(label: 'Local search only'),
                                VeilStatusPill(label: 'Opaque relay'),
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

bool shouldUseWideConversationLayout(double width) {
  return width >= 1120;
}

const String _conversationListViewStateStorageKey = 'conversation-list-view-state';

class ConversationListViewState {
  const ConversationListViewState({
    required this.query,
    required this.senderFilter,
    required this.typeFilter,
    required this.dateFilter,
    this.selectedConversationId,
    this.lastNavigationRequestId = 0,
  });

  final String query;
  final String? selectedConversationId;
  final MessageSearchSenderFilter senderFilter;
  final MessageSearchTypeFilter typeFilter;
  final MessageSearchDateFilter dateFilter;
  final int lastNavigationRequestId;
}

MessageNavigationTarget issueMessageNavigationTarget({
  required String messageId,
  required String query,
  required int requestId,
}) {
  return MessageNavigationTarget(
    messageId: messageId,
    requestId: requestId,
    query: query.trim(),
  );
}

List<MessageSearchResult> mergeArchiveSearchResults(
  List<MessageSearchResult> existing,
  List<MessageSearchResult> incoming,
) {
  final merged = <MessageSearchResult>[];
  final seenMessageIds = <String>{};

  for (final item in [...existing, ...incoming]) {
    if (!seenMessageIds.add(item.messageId)) {
      continue;
    }
    merged.add(item);
  }

  return merged;
}

Map<String, Object?> encodeConversationListViewState(
  ConversationListViewState state,
) {
  return <String, Object?>{
    'query': state.query.trim(),
    'selectedConversationId': state.selectedConversationId,
    'senderFilter': state.senderFilter.name,
    'typeFilter': state.typeFilter.name,
    'dateFilter': state.dateFilter.name,
    'lastNavigationRequestId': state.lastNavigationRequestId,
  };
}

ConversationListViewState? decodeConversationListViewState(Object? raw) {
  if (raw is! Map) {
    return null;
  }
  final query = raw['query'];
  final senderFilter = _messageSearchSenderFilterByName(raw['senderFilter']);
  final typeFilter = _messageSearchTypeFilterByName(raw['typeFilter']);
  final dateFilter = _messageSearchDateFilterByName(raw['dateFilter']);
  if (query is! String ||
      senderFilter == null ||
      typeFilter == null ||
      dateFilter == null) {
    return null;
  }
  final selectedConversationId = raw['selectedConversationId'];
  final lastNavigationRequestId = raw['lastNavigationRequestId'];
  return ConversationListViewState(
    query: query,
    selectedConversationId:
        selectedConversationId is String ? selectedConversationId : null,
    senderFilter: senderFilter,
    typeFilter: typeFilter,
    dateFilter: dateFilter,
    lastNavigationRequestId:
        lastNavigationRequestId is int ? lastNavigationRequestId : 0,
  );
}

MessageSearchSenderFilter? _messageSearchSenderFilterByName(Object? value) {
  return _enumByName(MessageSearchSenderFilter.values, value);
}

MessageSearchTypeFilter? _messageSearchTypeFilterByName(Object? value) {
  return _enumByName(MessageSearchTypeFilter.values, value);
}

MessageSearchDateFilter? _messageSearchDateFilterByName(Object? value) {
  return _enumByName(MessageSearchDateFilter.values, value);
}

T? _enumByName<T extends Enum>(List<T> values, Object? value) {
  if (value is! String) {
    return null;
  }
  for (final candidate in values) {
    if (candidate.name == value) {
      return candidate;
    }
  }
  return null;
}

List<ConversationPreview> filterConversationPreviews(
  List<ConversationPreview> conversations,
  String query,
) {
  final normalizedQuery = query.trim().toLowerCase();
  if (normalizedQuery.isEmpty) {
    return conversations;
  }

  final ranked = <({int score, ConversationPreview conversation})>[];
  for (final conversation in conversations) {
    final handle = conversation.peerHandle.toLowerCase();
    final displayName = (conversation.peerDisplayName ?? '').toLowerCase();
    final matchScore = _conversationSearchScore(
      query: normalizedQuery,
      handle: handle,
      displayName: displayName,
    );
    if (matchScore == null) {
      continue;
    }
    ranked.add((score: matchScore, conversation: conversation));
  }

  ranked.sort((a, b) {
    final scoreCompare = a.score.compareTo(b.score);
    if (scoreCompare != 0) {
      return scoreCompare;
    }
    final updatedAtCompare =
        b.conversation.updatedAt.compareTo(a.conversation.updatedAt);
    if (updatedAtCompare != 0) {
      return updatedAtCompare;
    }
    return a.conversation.peerHandle.compareTo(b.conversation.peerHandle);
  });

  return ranked.map((entry) => entry.conversation).toList(growable: false);
}

int? _conversationSearchScore({
  required String query,
  required String handle,
  required String displayName,
}) {
  if (handle == query) {
    return 0;
  }
  if (displayName == query) {
    return 10;
  }
  if (handle.startsWith(query)) {
    return 20;
  }
  if (displayName.startsWith(query)) {
    return 30;
  }

  final handleIndex = handle.indexOf(query);
  if (handleIndex >= 0) {
    return 40 + handleIndex;
  }

  final displayIndex = displayName.indexOf(query);
  if (displayIndex >= 0) {
    return 80 + displayIndex;
  }

  return null;
}

class _ConversationListPane extends StatelessWidget {
  const _ConversationListPane({
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
    required this.subtitleForConversation,
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
  final List<ConversationPreview> conversations;
  final List<MessageSearchResult> archiveResults;
  final bool searchingArchive;
  final bool archiveHasMore;
  final TextEditingController searchController;
  final MessageSearchSenderFilter senderFilter;
  final MessageSearchTypeFilter typeFilter;
  final MessageSearchDateFilter dateFilter;
  final String Function(ConversationPreview item, VeilMessengerController controller)
      subtitleForConversation;
  final DateFormat timeFormat;
  final String? selectedConversationId;
  final ValueChanged<String> onSelectConversation;
  final ValueChanged<MessageSearchResult> onSelectMessageResult;
  final VoidCallback onLoadMoreMessageResults;
  final ValueChanged<MessageSearchSenderFilter> onSenderFilterChanged;
  final ValueChanged<MessageSearchTypeFilter> onTypeFilterChanged;
  final ValueChanged<MessageSearchDateFilter> onDateFilterChanged;

  @override
  Widget build(BuildContext context) {
    final hasSearchQuery = searchController.text.trim().isNotEmpty;
    final children = <Widget>[
      VeilHeroPanel(
        eyebrow: 'DIRECT CONVERSATIONS',
        title: session.displayName?.isNotEmpty == true
            ? session.displayName!
            : '@${session.handle ?? 'unbound'}',
        body: controller.realtimeConnected
            ? 'Relay connected. Opaque envelopes only.'
            : 'Relay idle. Pulling the latest encrypted state.',
        bottom: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            VeilStatusPill(
              label: controller.realtimeConnected ? 'Relay linked' : 'Relay idle',
              tone:
                  controller.realtimeConnected ? VeilBannerTone.good : VeilBannerTone.warn,
            ),
            VeilStatusPill(
              label: conversations.isEmpty
                  ? '0 conversations'
                  : '${conversations.length} conversations',
            ),
            const VeilStatusPill(label: 'No backup'),
          ],
        ),
      ),
      const SizedBox(height: VeilSpace.md),
      VeilMetricStrip(
        items: [
          VeilMetricItem(
            label: 'Relay',
            value: controller.realtimeConnected ? 'Linked' : 'Idle',
          ),
          VeilMetricItem(
            label: 'Local search',
            value: hasSearchQuery ? 'Active' : 'Ready',
          ),
          VeilMetricItem(
            label: 'Conversations',
            value: '${conversations.length}',
          ),
        ],
      ),
      if (controller.errorMessage != null) ...[
        const SizedBox(height: VeilSpace.md),
        VeilInlineBanner(
          title: 'Sync issue',
          message: controller.errorMessage!,
          tone: VeilBannerTone.danger,
        ),
      ],
      const SizedBox(height: VeilSpace.md),
      VeilFieldBlock(
        label: 'LOCAL SEARCH INDEX',
        caption:
            'Search stays on this device. Handles, cached previews, and decrypted local index entries only.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: searchController,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search_rounded),
                hintText: 'Search conversations and cached messages',
                suffixIcon: searchController.text.trim().isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
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
                children: [
                  _SearchChip<MessageSearchSenderFilter>(
                    value: MessageSearchSenderFilter.all,
                    groupValue: senderFilter,
                    label: 'All senders',
                    onSelected: onSenderFilterChanged,
                  ),
                  _SearchChip<MessageSearchSenderFilter>(
                    value: MessageSearchSenderFilter.mine,
                    groupValue: senderFilter,
                    label: 'Mine',
                    onSelected: onSenderFilterChanged,
                  ),
                  _SearchChip<MessageSearchSenderFilter>(
                    value: MessageSearchSenderFilter.theirs,
                    groupValue: senderFilter,
                    label: 'Theirs',
                    onSelected: onSenderFilterChanged,
                  ),
                  _SearchChip<MessageSearchTypeFilter>(
                    value: MessageSearchTypeFilter.all,
                    groupValue: typeFilter,
                    label: 'All types',
                    onSelected: onTypeFilterChanged,
                  ),
                  _SearchChip<MessageSearchTypeFilter>(
                    value: MessageSearchTypeFilter.text,
                    groupValue: typeFilter,
                    label: 'Text',
                    onSelected: onTypeFilterChanged,
                  ),
                  _SearchChip<MessageSearchTypeFilter>(
                    value: MessageSearchTypeFilter.media,
                    groupValue: typeFilter,
                    label: 'Media',
                    onSelected: onTypeFilterChanged,
                  ),
                  _SearchChip<MessageSearchDateFilter>(
                    value: MessageSearchDateFilter.any,
                    groupValue: dateFilter,
                    label: 'Any date',
                    onSelected: onDateFilterChanged,
                  ),
                  _SearchChip<MessageSearchDateFilter>(
                    value: MessageSearchDateFilter.last7Days,
                    groupValue: dateFilter,
                    label: 'Last 7d',
                    onSelected: onDateFilterChanged,
                  ),
                  _SearchChip<MessageSearchDateFilter>(
                    value: MessageSearchDateFilter.last30Days,
                    groupValue: dateFilter,
                    label: 'Last 30d',
                    onSelected: onDateFilterChanged,
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: VeilSpace.md),
      VeilSectionLabel(
        'CONVERSATIONS',
        trailing: hasSearchQuery
            ? Text(
                '${conversations.length} match${conversations.length == 1 ? '' : 'es'}',
                style: Theme.of(context).textTheme.bodySmall,
              )
            : null,
      ),
      const SizedBox(height: VeilSpace.sm),
    ];

    if (conversations.isEmpty && controller.isBusy) {
      children.addAll(const [
        SizedBox(height: VeilSpace.xl),
        VeilSurfaceCard(
          toned: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              VeilSkeletonLine(width: 96),
              SizedBox(height: VeilSpace.md),
              VeilSkeletonLine(width: 220, height: 18),
              SizedBox(height: VeilSpace.sm),
              VeilSkeletonLine(width: double.infinity),
              SizedBox(height: VeilSpace.sm),
              VeilSkeletonLine(width: 180),
            ],
          ),
        ),
        SizedBox(height: VeilSpace.sm),
        VeilSurfaceCard(
          toned: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              VeilSkeletonLine(width: 84),
              SizedBox(height: VeilSpace.md),
              VeilSkeletonLine(width: 200, height: 18),
              SizedBox(height: VeilSpace.sm),
              VeilSkeletonLine(width: double.infinity),
            ],
          ),
        ),
      ]);
    } else if (conversations.isEmpty) {
      children.add(
        Padding(
          padding: const EdgeInsets.only(top: 72),
          child: VeilEmptyState(
            title: hasSearchQuery
                ? 'No matching conversations'
                : 'No direct conversations yet',
            body: hasSearchQuery
                ? 'This device did not find a matching handle or display label.'
                : 'Start with a handle. VEIL keeps discovery manual and private.',
            icon: hasSearchQuery ? Icons.search_off_rounded : Icons.forum_outlined,
            action: VeilButton(
              onPressed: () => context.push('/start-chat'),
              label: 'Start direct chat',
              tone: VeilButtonTone.secondary,
            ),
          ),
        ),
      );
    } else {
      children.addAll(
        conversations.map((item) {
          final isSelected = item.id == selectedConversationId;
          return Padding(
            padding: const EdgeInsets.only(bottom: VeilSpace.sm),
            child: AnimatedContainer(
              duration: VeilMotion.normal,
              curve: Curves.easeOutCubic,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(VeilRadius.lg),
                boxShadow: isSelected
                    ? const [
                        BoxShadow(
                          color: Color(0x22000000),
                          blurRadius: 24,
                          offset: Offset(0, 12),
                        ),
                      ]
                    : null,
              ),
              child: Theme(
                data: Theme.of(context).copyWith(
                  cardTheme: Theme.of(context).cardTheme.copyWith(
                        color: isSelected
                            ? const Color(0xFF151E28)
                            : Theme.of(context).cardTheme.color,
                      ),
                ),
                child: VeilConversationCard(
                  title: item.peerDisplayName ?? item.peerHandle,
                  handle: item.peerHandle,
                  subtitle: subtitleForConversation(item, controller),
                  timestamp: timeFormat.format(item.updatedAt),
                  selected: isSelected,
                  meta: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      const VeilStatusPill(label: 'Direct'),
                      if (controller.pendingCountFor(item.id) > 0)
                        VeilStatusPill(
                          label: controller.pendingCountFor(item.id) == 1
                              ? '1 queued'
                              : '${controller.pendingCountFor(item.id)} queued',
                          tone: VeilBannerTone.warn,
                        ),
                    ],
                  ),
                  expiryLabel: item.lastEnvelope?.expiresAt == null
                      ? null
                      : formatMessageExpiry(item.lastEnvelope!.expiresAt!),
                  onTap: () => onSelectConversation(item.id),
                ),
              ),
            ),
          );
        }),
      );
    }

    if (hasSearchQuery) {
      children.addAll([
        const SizedBox(height: VeilSpace.md),
        VeilSectionLabel(
          'MESSAGES',
          trailing: searchingArchive
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(
                  '${archiveResults.length} result${archiveResults.length == 1 ? '' : 's'}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
        ),
        const SizedBox(height: VeilSpace.sm),
      ]);

      if (!searchingArchive && archiveResults.isEmpty) {
        children.add(
          const VeilEmptyState(
            title: 'No local message matches',
            body: 'This device did not find matching cached message text for the current filters.',
            icon: Icons.manage_search_rounded,
          ),
        );
      } else {
        children.addAll(
          archiveResults.map(
            (result) => Padding(
              padding: const EdgeInsets.only(bottom: VeilSpace.sm),
              child: VeilListTileCard(
                eyebrow: '${result.isMine ? 'You' : 'Peer'} | ${_messageTypeLabel(result.messageKind)}',
                leading: Icon(
                  switch (result.messageKind) {
                    MessageKind.text => Icons.chat_bubble_outline_rounded,
                    MessageKind.image => Icons.image_outlined,
                    MessageKind.file => Icons.attach_file_rounded,
                    MessageKind.system => Icons.info_outline_rounded,
                  },
                ),
                title: result.title,
                subtitle: result.bodySnippet,
                subtitleWidget: _MessageSearchResultSubtitle(
                  result: result,
                  query: searchController.text,
                  timeFormat: timeFormat,
                ),
                trailing: const Icon(Icons.north_east_rounded, size: 18),
                onTap: () => onSelectMessageResult(result),
              ),
            ),
          ),
        );
        if (archiveHasMore) {
          children.add(
            Padding(
              padding: const EdgeInsets.only(top: VeilSpace.xs, bottom: VeilSpace.sm),
              child: Align(
                alignment: Alignment.centerLeft,
                child: VeilButton(
                  expanded: false,
                  onPressed: searchingArchive ? null : onLoadMoreMessageResults,
                  tone: VeilButtonTone.secondary,
                  label: searchingArchive ? 'Loading more' : 'Load more results',
                  icon: Icons.expand_more_rounded,
                ),
              ),
            ),
          );
        }
      }
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
                  label: 'Start direct chat',
                  tone: VeilButtonTone.secondary,
                  icon: Icons.add_comment_outlined,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

String _messageTypeLabel(MessageKind kind) {
  return switch (kind) {
    MessageKind.text => 'Text',
    MessageKind.image => 'Image',
    MessageKind.file => 'Attachment',
    MessageKind.system => 'System',
  };
}

String _messageDateLabel(DateTime sentAt, DateFormat timeFormat) {
  final now = DateTime.now();
  if (sentAt.year == now.year && sentAt.month == now.month && sentAt.day == now.day) {
    return timeFormat.format(sentAt);
  }
  return DateFormat('MMM d').format(sentAt);
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

class _MessageSearchResultSubtitle extends StatelessWidget {
  const _MessageSearchResultSubtitle({
    required this.result,
    required this.query,
    required this.timeFormat,
  });

  final MessageSearchResult result;
  final String query;
  final DateFormat timeFormat;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.veilPalette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${result.isMine ? 'You' : 'Peer'} | ${_messageTypeLabel(result.messageKind)} | ${_messageDateLabel(result.sentAt, timeFormat)}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: palette.textSubtle,
          ),
        ),
        const SizedBox(height: VeilSpace.xxs),
        RichText(
          text: TextSpan(
            style: theme.textTheme.bodyMedium,
            children: buildSearchHighlightTextSpans(
              text: result.bodySnippet,
              query: query,
              highlightStyle: theme.textTheme.bodyMedium?.copyWith(
                color: palette.text,
                fontWeight: FontWeight.w700,
              ),
              baseStyle: theme.textTheme.bodyMedium,
            ),
          ),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

List<TextSpan> buildSearchHighlightTextSpans({
  required String text,
  required String query,
  TextStyle? baseStyle,
  TextStyle? highlightStyle,
}) {
  final normalizedQuery = query.trim().toLowerCase();
  if (normalizedQuery.isEmpty) {
    return <TextSpan>[TextSpan(text: text, style: baseStyle)];
  }

  final spans = <TextSpan>[];
  final lowerText = text.toLowerCase();
  var cursor = 0;
  while (cursor < text.length) {
    final matchIndex = lowerText.indexOf(normalizedQuery, cursor);
    if (matchIndex < 0) {
      spans.add(TextSpan(text: text.substring(cursor), style: baseStyle));
      break;
    }
    if (matchIndex > cursor) {
      spans.add(
        TextSpan(text: text.substring(cursor, matchIndex), style: baseStyle),
      );
    }
    spans.add(
      TextSpan(
        text: text.substring(matchIndex, matchIndex + normalizedQuery.length),
        style: highlightStyle ?? baseStyle,
      ),
    );
    cursor = matchIndex + normalizedQuery.length;
  }
  return spans;
}
