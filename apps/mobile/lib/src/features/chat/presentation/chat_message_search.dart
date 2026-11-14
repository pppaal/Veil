import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_state.dart';
import '../../conversations/data/conversation_models.dart';

/// Search over a chat's loaded messages: the query field, looked up on the
/// messenger 180 ms after it last changed, and the ids of the messages that
/// matched the latest query.
mixin ChatMessageSearch<W extends ConsumerStatefulWidget> on ConsumerState<W> {
  final searchController = TextEditingController();
  Timer? _searchDebounce;
  Set<String> _matchingMessageIds = <String>{};
  bool _isSearchingMessages = false;

  /// The conversation the chat shows.
  String get conversationId;

  /// Whether the lookup for the current query is still running.
  bool get isSearchingMessages => _isSearchingMessages;

  bool get hasSearchQuery => searchController.text.trim().isNotEmpty;

  /// [messages] narrowed to the matches of the query, while there is one.
  List<ChatMessage> searchMatches(List<ChatMessage> messages) {
    if (!hasSearchQuery) {
      return messages;
    }
    return messages
        .where((message) => _matchingMessageIds.contains(message.id))
        .toList();
  }

  /// Drops the query and its matches, as when the chat switches to another
  /// conversation.
  void resetSearch() {
    _matchingMessageIds = <String>{};
    searchController.clear();
  }

  @override
  void initState() {
    super.initState();
    searchController.addListener(_handleSearchChanged);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    searchController.dispose();
    super.dispose();
  }

  void _handleSearchChanged() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(
      const Duration(milliseconds: 180),
      () => unawaited(runSearch()),
    );
  }

  /// Looks the current query up now. An answer for a query the field no
  /// longer holds is dropped.
  Future<void> runSearch() async {
    final query = searchController.text.trim();
    if (query.isEmpty) {
      if (!mounted) {
        return;
      }
      setState(() {
        _matchingMessageIds = <String>{};
        _isSearchingMessages = false;
      });
      return;
    }

    if (mounted) {
      setState(() => _isSearchingMessages = true);
    }

    final matches =
        await ref.read(messengerControllerProvider).searchLoadedMessageIds(
              conversationId,
              query: query,
            );

    if (!mounted || searchController.text.trim() != query) {
      return;
    }

    setState(() {
      _matchingMessageIds = matches.toSet();
      _isSearchingMessages = false;
    });
  }
}
