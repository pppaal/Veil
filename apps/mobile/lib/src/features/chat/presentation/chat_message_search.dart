import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_state.dart';

/// Search over a chat's loaded messages, as Signal and Telegram do it: the
/// query field, looked up on the messenger 180 ms after it last changed;
/// the messages that matched, oldest first; and which of them is shown,
/// the newest when the answer comes in. Every message stays in the list,
/// and the chat scrolls to the hit that is shown ([showSearchHit]).
mixin ChatMessageSearch<W extends ConsumerStatefulWidget> on ConsumerState<W> {
  final searchController = TextEditingController();
  Timer? _searchDebounce;
  List<String> _hitIds = const <String>[];
  int _hitIndex = -1;
  bool _isSearchingMessages = false;

  /// The conversation the chat shows.
  String get conversationId;

  /// Brings the hit [messageId] into view.
  void showSearchHit(String messageId);

  /// Whether the lookup for the current query is still running.
  bool get isSearchingMessages => _isSearchingMessages;

  bool get hasSearchQuery => searchController.text.trim().isNotEmpty;

  /// How many messages matched the query.
  int get searchHitCount => _hitIds.length;

  /// Which of them is shown, counted from 0 at the oldest; -1 with none.
  int get searchHitIndex => _hitIndex;

  /// The message the search shows now, or null.
  String? get currentSearchHit => _hitIndex < 0 || _hitIndex >= _hitIds.length ? null : _hitIds[_hitIndex];

  /// Shows the hit before the one shown, if there is one.
  void showOlderSearchHit() => _moveTo(_hitIndex - 1);

  /// Shows the hit after the one shown, if there is one.
  void showNewerSearchHit() => _moveTo(_hitIndex + 1);

  void _moveTo(int index) {
    if (index < 0 || index >= _hitIds.length || index == _hitIndex) return;
    setState(() => _hitIndex = index);
    showSearchHit(_hitIds[index]);
  }

  /// Drops the query and its matches, as when the chat switches to another
  /// conversation.
  void resetSearch() {
    _hitIds = const <String>[];
    _hitIndex = -1;
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
        _hitIds = const <String>[];
        _hitIndex = -1;
        _isSearchingMessages = false;
      });
      return;
    }

    if (mounted) {
      setState(() => _isSearchingMessages = true);
    }

    final messenger = ref.read(messengerControllerProvider);
    final matches = (await messenger.searchLoadedMessageIds(conversationId, query: query)).toSet();

    if (!mounted || searchController.text.trim() != query) {
      return;
    }

    final hits = [
      for (final message in messenger.messagesFor(conversationId))
        if (matches.contains(message.id)) message.id,
    ];
    setState(() {
      _hitIds = hits;
      _hitIndex = hits.length - 1;
      _isSearchingMessages = false;
    });
    if (hits.isNotEmpty) showSearchHit(hits.last);
  }
}
