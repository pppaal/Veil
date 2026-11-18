import 'dart:async';

import '../../../../core/domain/conversation_read_mark.dart';
import '../../../../core/storage/conversation_cache_service.dart';
import '../conversation_models.dart';
import 'conversation_merge.dart';
import 'conversation_peer_bindings.dart';
import 'message_merge.dart';

/// Told which parts of the state changed, e.g. to persist or re-arm timers.
abstract interface class MessengerStateObserver {
  void conversationsChanged();

  void messagesChanged(String conversationId);

  void pagingChanged(String conversationId);
}

/// Told when what has been read changes: an observer that also implements
/// this hears it (to persist a mark, or to count again).
abstract interface class ReadMarkObserver {
  void readMarkChanged(String conversationId);

  /// The baseline marker was spent: the first relay list set its marks.
  void baselineSpent();
}

/// Last step of every merge, for derived fields kept on the messages
/// (reactions, receipts that arrived before their message).
typedef MessageDecorator = List<ChatMessage> Function(String conversationId, List<ChatMessage> messages);

/// The messenger's in-memory state: the conversation list, the loaded
/// messages of each conversation and their history paging.
///
/// Every mutation tells the observers what changed and asks for one
/// listener notification per microtask, however many mutations a step makes.
class MessengerStateStore {
  MessengerStateStore({
    required void Function() onChanged,
    MessageDecorator? decorate,
    void Function(String conversationId)? onLatestMessageChanged,
  })  : _onChanged = onChanged,
        _decorate = decorate,
        _onLatestMessageChanged = onLatestMessageChanged;

  final void Function() _onChanged;
  final MessageDecorator? _decorate;
  final void Function(String conversationId)? _onLatestMessageChanged;
  final List<MessengerStateObserver> _observers = [];
  bool _notificationScheduled = false;

  List<ConversationPreview> _conversations = [];
  final Map<String, List<ChatMessage>> _messages = {};
  final Map<String, ConversationPagingState> _paging = {};
  final Map<String, ConversationReadMark> _readMarks = {};
  bool _baselinePending = true;
  bool _listedByRelay = false;
  Set<String> _hydratedIds = const {};

  /// The conversation the user is looking at right now, or null. What
  /// arrives there is read (ReadStateService) and raises no notification.
  String? activeConversationId;

  void addObserver(MessengerStateObserver observer) => _observers.add(observer);

  /// Schedules a single listener notification for everything changed in
  /// the current microtask.
  void changed() {
    if (_notificationScheduled) return;
    _notificationScheduled = true;
    scheduleMicrotask(() {
      _notificationScheduled = false;
      _onChanged();
    });
  }

  List<ConversationPreview> get conversations => _conversations;

  ConversationPreview? conversationById(String conversationId) {
    for (final conversation in _conversations) {
      if (conversation.id == conversationId) return conversation;
    }
    return null;
  }

  /// The listed conversation, failing the way a missing one always did.
  ConversationPreview requireConversation(String conversationId) =>
      conversationById(conversationId) ?? (throw StateError('No element'));

  /// Applies a fresh relay list over the local previews (see
  /// mergeConversationPreviews), then lets [pin] hold each preview to what
  /// this device pinned for it. Returns the ids [pin] overruled, or null
  /// when [stillCurrent] says the list no longer belongs to the session
  /// once [pin] is done, and nothing was applied.
  Future<List<String>?> replaceConversations(
    List<ConversationPreview> fetched, {
    required Map<String, ConversationPeer> bound,
    required Future<(List<ConversationPreview>, List<String>)> Function(List<ConversationPreview> merged) pin,
    bool Function()? stillCurrent,
  }) async {
    final (listed, overruled) = await pin(mergeConversationPreviews(_conversations, fetched, bound: bound));
    if (stillCurrent != null && !stillCurrent()) return null;
    _conversations = listed..sort(_byRecency);
    _listedByRelay = true;
    _conversationsChanged();
    return overruled;
  }

  /// Whether a relay list was applied since the state was last hydrated or
  /// cleared.
  bool get listedByRelay => _listedByRelay;

  /// The conversations the cache held when the state was last hydrated:
  /// what the first relay list after a start is compared with, so a chat
  /// that left while the app was closed is seen to have left.
  Set<String> get hydratedIds => _hydratedIds;

  /// Whether the next relay list is this device's first (the cache held the
  /// baseline marker, or there is no cache to hold anything): what it lists
  /// is read through its last message.
  bool get baselinePending => _baselinePending;

  ConversationReadMark? readMarkOf(String conversationId) => _readMarks[conversationId];

  Map<String, ConversationReadMark> get readMarks => Map.unmodifiable(_readMarks);

  /// Sets what has been read of [conversationId]; the same mark again
  /// changes nothing.
  void setReadMark(String conversationId, ConversationReadMark mark) {
    if (_readMarks[conversationId] == mark) return;
    _readMarks[conversationId] = mark;
    for (final observer in _observers) {
      if (observer is ReadMarkObserver) (observer as ReadMarkObserver).readMarkChanged(conversationId);
    }
    changed();
  }

  /// Sets the marks the first relay list gives and spends the baseline, so
  /// the writer deletes the marker in the same write as these marks.
  void spendBaseline(Map<String, ConversationReadMark> marks) {
    marks.forEach(setReadMark);
    _baselinePending = false;
    for (final observer in _observers) {
      if (observer is ReadMarkObserver) (observer as ReadMarkObserver).baselineSpent();
    }
    changed();
  }

  /// Empties the list; the cache keeps its rows.
  void clearConversations() {
    _conversations = [];
    changed();
  }

  /// Replaces the conversation [conversationId] with [update] of it. False
  /// when it is not listed or [update] returned it unchanged.
  bool updateConversation(String conversationId, ConversationPreview Function(ConversationPreview) update) {
    final index = _conversations.indexWhere((item) => item.id == conversationId);
    if (index == -1) return false;
    final current = _conversations[index];
    final updated = update(current);
    if (identical(updated, current)) return false;
    _conversations = List<ConversationPreview>.of(_conversations)..[index] = updated;
    _conversationsChanged();
    return true;
  }

  Iterable<String> get loadedConversationIds => _messages.keys;

  /// The loaded messages of [conversationId]; empty when none are.
  List<ChatMessage> messagesOf(String conversationId) => _messages[conversationId] ?? const [];

  bool hasMessagesLoaded(String conversationId) => _messages.containsKey(conversationId);

  /// The listed conversations whose last message this device has never
  /// loaded, newest first: the list cannot say what that message is until
  /// their history has been fetched. One whose last message expired by
  /// [now] has nothing left to show.
  List<String> unloadedWithLastMessage(DateTime now) => [
        for (final conversation in _conversations)
          if (conversation.lastEnvelope case final last?
              when !_messages.containsKey(conversation.id) && !_isExpired(last.expiresAt, now))
            conversation.id,
      ];

  int pendingCountFor(String conversationId) =>
      messagesOf(conversationId).where((message) => message.isPending || message.hasFailed).length;

  void setMessages(String conversationId, List<ChatMessage> messages) {
    _messages[conversationId] = messages;
    _messagesChanged(conversationId);
  }

  /// Merges [incoming] (see mergeMessageCollections) and moves the
  /// conversation's preview to its latest message.
  void mergeMessages(String conversationId, List<ChatMessage> incoming) {
    final merged = mergeMessageCollections(messagesOf(conversationId), incoming);
    _messages[conversationId] = _decorate?.call(conversationId, merged) ?? merged;
    _messagesChanged(conversationId);
    syncPreviewFromMessages(conversationId);
  }

  /// Runs [update] on every loaded message [matches] accepts, in one
  /// conversation or in all. Returns whether any message changed.
  bool updateMessagesWhere(
    bool Function(ChatMessage message) matches,
    ChatMessage Function(ChatMessage message) update, {
    String? inConversation,
  }) {
    var anyChanged = false;
    final conversationIds = inConversation == null ? _messages.keys.toList() : [inConversation];
    for (final conversationId in conversationIds) {
      final messages = _messages[conversationId];
      if (messages == null) continue;
      var changed = false;
      final updated = [
        for (final message in messages)
          if (matches(message)) _tracked(update(message), message, () => changed = true) else message,
      ];
      if (!changed) continue;
      anyChanged = true;
      setMessages(conversationId, updated);
    }
    return anyChanged;
  }

  /// Drops every loaded message that expired by [now], and the previews of
  /// conversations without loaded messages whose last message did. Returns
  /// the messages dropped and whether anything changed.
  ({List<ChatMessage> expired, bool changed}) removeExpired(DateTime now) {
    final expired = <ChatMessage>[];
    for (final MapEntry(key: conversationId, value: messages) in _messages.entries.toList()) {
      final retained = messages.where((message) => !_isExpired(message.expiresAt, now)).toList(growable: true);
      if (retained.length == messages.length) continue;
      expired.addAll(messages.where((message) => _isExpired(message.expiresAt, now)));
      setMessages(conversationId, retained);
      syncPreviewFromMessages(conversationId);
    }
    var previewsDropped = false;
    final updated = [
      for (final conversation in _conversations)
        if (!_messages.containsKey(conversation.id) && _isExpired(conversation.lastEnvelope?.expiresAt, now))
          _tracked(conversation.copyWith(lastEnvelope: null), conversation, () => previewsDropped = true)
        else
          conversation,
    ];
    final changed = previewsDropped || expired.isNotEmpty;
    if (changed) {
      _conversations = updated..sort(_byRecency);
      _conversationsChanged();
    }
    return (expired: expired, changed: changed);
  }

  /// The earliest expiry of anything [removeExpired] would drop; null when
  /// nothing loaded or listed expires.
  DateTime? nextExpiry() {
    DateTime? earliest;
    void consider(DateTime? expiresAt) {
      if (expiresAt != null && (earliest == null || expiresAt.isBefore(earliest!))) earliest = expiresAt;
    }

    for (final message in _messages.values.expand((messages) => messages)) {
      consider(message.expiresAt);
    }
    for (final conversation in _conversations) {
      if (!_messages.containsKey(conversation.id)) consider(conversation.lastEnvelope?.expiresAt);
    }
    return earliest;
  }

  /// Points the conversation's preview at its latest loaded message.
  void syncPreviewFromMessages(String conversationId) {
    final messages = _messages[conversationId];
    if (messages == null) return;
    final index = _conversations.indexWhere((item) => item.id == conversationId);
    if (index == -1) return;
    final latest = messages.lastOrNull;
    final current = _conversations[index];
    _conversations[index] = current.copyWith(
      lastEnvelope: latest?.envelope,
      updatedAt: latest?.sentAt ?? current.updatedAt,
    );
    _conversations.sort(_byRecency);
    _conversationsChanged();
    _onLatestMessageChanged?.call(conversationId);
  }

  ConversationPagingState pagingFor(String conversationId) =>
      _paging[conversationId] ?? const ConversationPagingState();

  bool hasPagingFor(String conversationId) => _paging.containsKey(conversationId);

  void setPaging(String conversationId, ConversationPagingState state) {
    _paging[conversationId] = state;
    for (final observer in _observers) {
      observer.pagingChanged(conversationId);
    }
  }

  /// Replaces everything with what the cache held: [conversations] with
  /// their [messages], and from [snapshot] their paging (the default for one
  /// it has none of), the read marks and the baseline marker.
  void hydrate({
    required List<ConversationPreview> conversations,
    required Map<String, List<ChatMessage>> messages,
    required ConversationCacheSnapshot snapshot,
  }) {
    _conversations = conversations;
    _messages
      ..clear()
      ..addAll(messages);
    _paging
      ..clear()
      ..addAll({
        for (final conversation in conversations)
          conversation.id: snapshot.paging[conversation.id] ?? const ConversationPagingState(),
      });
    _readMarks
      ..clear()
      ..addAll(snapshot.readMarks);
    _baselinePending = snapshot.baselinePending;
    _listedByRelay = false;
    _hydratedIds = {for (final conversation in conversations) conversation.id};
    changed();
  }

  /// Forgets everything. The next identity is new or moved here, as on a
  /// first install, so its first list is read through.
  void clear() {
    _conversations = [];
    _messages.clear();
    _paging.clear();
    _readMarks.clear();
    _baselinePending = true;
    _listedByRelay = false;
    _hydratedIds = const {};
    activeConversationId = null;
    changed();
  }

  void _conversationsChanged() {
    for (final observer in _observers) {
      observer.conversationsChanged();
    }
    changed();
  }

  void _messagesChanged(String conversationId) {
    for (final observer in _observers) {
      observer.messagesChanged(conversationId);
    }
    changed();
  }

  static T _tracked<T>(T updated, T current, void Function() onChange) {
    if (!identical(updated, current)) onChange();
    return updated;
  }

  static int _byRecency(ConversationPreview a, ConversationPreview b) => b.updatedAt.compareTo(a.updatedAt);

  static bool _isExpired(DateTime? expiresAt, DateTime now) => expiresAt != null && !expiresAt.isAfter(now);
}
