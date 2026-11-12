import 'dart:async';

import '../../../../core/crypto/crypto_engine.dart';
import '../../../../core/storage/conversation_cache_service.dart';
import '../conversation_models.dart';
import 'messenger_state_store.dart';

/// What the cache held when the messenger started.
typedef CachedMessengerState = ({ConversationCacheSnapshot snapshot, List<PendingMessageRecord> pending});

/// Writes the messenger's state to the encrypted cache.
///
/// Every write goes through one queue, so writes land in the order they
/// were made and a slow one can never be overtaken by a newer one and then
/// overwrite it. State changes only mark what changed; a flush, 100 ms
/// after the last change (at most 1 s after the first), when the app
/// pauses, or when the messenger is disposed, writes the rows that differ
/// from what this writer last wrote, read from the state as it is then.
/// Outbox records are written at once: a queued message must survive a
/// crash right after the send.
class MessengerPersistence implements MessengerStateObserver {
  MessengerPersistence({
    required ConversationCacheService? cache,
    required MessengerStateStore store,
    Duration debounce = const Duration(milliseconds: 100),
    Duration maxDelay = const Duration(seconds: 1),
  })  : _cache = cache,
        _store = store,
        _debounce = debounce,
        _maxDelay = maxDelay;

  final ConversationCacheService? _cache;
  final MessengerStateStore _store;
  final Duration _debounce;
  final Duration _maxDelay;

  bool _conversationsDirty = false;
  final Set<String> _messagesDirty = {};
  final Set<String> _pagingDirty = {};
  // What this writer knows the cache holds, by conversation and by message.
  // A conversation missing from [_writtenMessages] has rows this writer has
  // not seen, so its first write replaces them all.
  final Map<String, ConversationPreview> _writtenConversations = {};
  final Map<String, Map<String, ChatMessage>> _writtenMessages = {};
  Timer? _debounceTimer;
  Timer? _maxDelayTimer;
  // The last queued task, null while the queue is idle. Created per task,
  // never up front: a future made when the messenger was built belongs to
  // that zone, and work queued from another zone would wait on it.
  Future<void>? _tail;
  // Bumped when the identity changes: writes queued for the previous one
  // are dropped, so nothing of it lands in a cache wiped at sign-out.
  int _generation = 0;
  bool _disposed = false;

  @override
  void conversationsChanged() {
    _conversationsDirty = true;
    _schedule();
  }

  @override
  void messagesChanged(String conversationId) {
    _messagesDirty.add(conversationId);
    _schedule();
  }

  @override
  void pagingChanged(String conversationId) {
    _pagingDirty.add(conversationId);
    _schedule();
  }

  /// Reads everything the cache holds, after the writes queued before.
  /// Null without a cache.
  Future<CachedMessengerState?> hydrate() => _serialized(() async {
        final cache = _cache;
        if (cache == null) return null;
        await cache.purgeExpiredMessages();
        final snapshot = cache is IncrementalConversationCache
            ? await (cache as IncrementalConversationCache).readSnapshot()
            : await _readEachConversation(cache);
        _writtenConversations
          ..clear()
          ..addAll({for (final conversation in snapshot.conversations) conversation.id: conversation});
        _writtenMessages
          ..clear()
          ..addAll({
            for (final MapEntry(key: conversationId, value: messages) in snapshot.messages.entries)
              conversationId: {for (final message in messages) message.id: message},
          });
        return (snapshot: snapshot, pending: await cache.readPendingMessages());
      });

  Future<void> savePending(PendingMessageRecord pending) => _write(() async => _cache?.upsertPendingMessage(pending));

  Future<void> removePending(String clientMessageId) =>
      _write(() async => _cache?.removePendingMessage(clientMessageId));

  /// Deletes what expired in the cache, messages the app never loaded included.
  Future<void> purgeExpired() => _write(() async => _cache?.purgeExpiredMessages());

  /// Writes every pending change now.
  Future<void> flush() {
    _debounceTimer?.cancel();
    _maxDelayTimer?.cancel();
    _debounceTimer = null;
    _maxDelayTimer = null;
    return _write(_writeChanges);
  }

  /// Forgets the previous identity's unwritten changes and drops its queued
  /// writes.
  void reset() {
    _generation += 1;
    _debounceTimer?.cancel();
    _maxDelayTimer?.cancel();
    _debounceTimer = null;
    _maxDelayTimer = null;
    _conversationsDirty = false;
    _messagesDirty.clear();
    _pagingDirty.clear();
    _writtenConversations.clear();
    _writtenMessages.clear();
  }

  /// Writes what is still pending and stops scheduling.
  void dispose() {
    if (_disposed) return;
    unawaited(flush());
    _disposed = true;
  }

  void _schedule() {
    if (_disposed || _cache == null) return;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounce, () => unawaited(flush()));
    _maxDelayTimer ??= Timer(_maxDelay, () => unawaited(flush()));
  }

  // Queues a write for the current identity; it is dropped if the
  // identity changes before its turn.
  Future<void> _write(Future<void> Function() write) {
    final generation = _generation;
    return _serialized(() async {
      if (generation == _generation) await write();
    });
  }

  Future<T> _serialized<T>(Future<T> Function() task) {
    final previous = _tail;
    final result = previous == null ? task() : previous.then((_) => task());
    final tail = result.then<void>((_) {}, onError: (Object _) {});
    _tail = tail;
    tail.whenComplete(() {
      if (identical(_tail, tail)) _tail = null;
    }).ignore();
    return result;
  }

  Future<void> _writeChanges() async {
    final cache = _cache;
    if (cache == null) return;
    final conversationsDirty = _conversationsDirty;
    final messagesDirty = Set<String>.of(_messagesDirty);
    final pagingDirty = Set<String>.of(_pagingDirty);
    _conversationsDirty = false;
    _messagesDirty.clear();
    _pagingDirty.clear();
    if (!conversationsDirty && messagesDirty.isEmpty && pagingDirty.isEmpty) return;

    final listed = {for (final conversation in _store.conversations) conversation.id: conversation};
    // The cache refuses messages without their conversation; those of one the
    // list has not caught up with yet wait until it is listed.
    _messagesDirty.addAll(messagesDirty.where((id) => !listed.containsKey(id)));
    final written = {
      for (final id in messagesDirty)
        if (listed.containsKey(id)) id: List<ChatMessage>.of(_store.messagesOf(id)),
    };
    final changes = ConversationCacheChanges(
      conversations: [
        for (final conversation in listed.values)
          if (!_sameConversationRow(_writtenConversations[conversation.id], conversation)) conversation,
      ],
      replacedConversationIds: {
        for (final id in written.keys)
          if (!_writtenMessages.containsKey(id)) id,
      },
      messages: [
        for (final MapEntry(key: id, value: messages) in written.entries)
          for (final message in messages)
            if (!_sameMessageRow(_writtenMessages[id]?[message.id], message)) message,
      ],
      deletedMessageIds: {
        for (final MapEntry(key: id, value: messages) in written.entries)
          ...?_writtenMessages[id]?.keys.toSet().difference({for (final message in messages) message.id}),
      },
      paging: {
        for (final id in pagingDirty)
          if (listed.containsKey(id) && _store.hasPagingFor(id)) id: _store.pagingFor(id),
      },
    );
    if (changes.isEmpty) return;

    try {
      if (cache is IncrementalConversationCache) {
        await (cache as IncrementalConversationCache).writeChanges(changes);
      } else {
        await _writeWhole(cache, changes, written);
      }
    } catch (_) {
      // Kept for the next flush, which the next change schedules.
      _conversationsDirty |= conversationsDirty;
      _messagesDirty.addAll(written.keys);
      _pagingDirty.addAll(changes.paging.keys);
      return;
    }
    for (final conversation in changes.conversations) {
      _writtenConversations[conversation.id] = conversation;
    }
    for (final MapEntry(key: id, value: messages) in written.entries) {
      _writtenMessages[id] = {for (final message in messages) message.id: message};
    }
  }

  // Caches without row-level writes take each changed conversation whole.
  Future<void> _writeWhole(
    ConversationCacheService cache,
    ConversationCacheChanges changes,
    Map<String, List<ChatMessage>> written,
  ) async {
    if (changes.conversations.isNotEmpty || written.isNotEmpty) {
      await cache.storeConversations(_store.conversations);
    }
    for (final MapEntry(key: id, value: messages) in written.entries) {
      await cache.storeMessages(id, messages);
    }
    for (final MapEntry(key: id, value: state) in changes.paging.entries) {
      await cache.storePagingState(
        id,
        nextCursor: state.nextCursor,
        hasMoreHistory: state.hasMoreHistory,
        lastSyncedAt: state.lastSyncedAt,
      );
    }
  }

  static Future<ConversationCacheSnapshot> _readEachConversation(ConversationCacheService cache) async {
    final conversations = await cache.readConversations();
    return ConversationCacheSnapshot(
      conversations: conversations,
      messages: {for (final conversation in conversations) conversation.id: await cache.readMessages(conversation.id)},
      paging: {for (final conversation in conversations) conversation.id: await cache.readPagingState(conversation.id)},
    );
  }
}

// Whether the cache row of [written] already holds [current]: compares the
// columns the cache stores, not the fields only memory keeps.
bool _sameConversationRow(ConversationPreview? written, ConversationPreview current) {
  if (identical(written, current)) return true;
  if (written == null) return false;
  final a = written.recipientBundle;
  final b = current.recipientBundle;
  return written.peerHandle == current.peerHandle &&
      written.peerDisplayName == current.peerDisplayName &&
      written.updatedAt == current.updatedAt &&
      a.userId == b.userId &&
      a.deviceId == b.deviceId &&
      a.identityPublicKey == b.identityPublicKey &&
      a.signedPrekeyBundle == b.signedPrekeyBundle &&
      _sameEnvelope(written.lastEnvelope, current.lastEnvelope) &&
      written.lastEnvelope?.expiresAt == current.lastEnvelope?.expiresAt &&
      _sameSession(written.sessionState, current.sessionState);
}

bool _sameMessageRow(ChatMessage? written, ChatMessage current) {
  if (identical(written, current)) return true;
  if (written == null) return false;
  return written.clientMessageId == current.clientMessageId &&
      written.senderDeviceId == current.senderDeviceId &&
      written.sentAt == current.sentAt &&
      written.conversationOrder == current.conversationOrder &&
      written.expiresAt == current.expiresAt &&
      written.deliveryState == current.deliveryState &&
      written.deliveredAt == current.deliveredAt &&
      written.readAt == current.readAt &&
      written.searchableBody == current.searchableBody &&
      _sameEnvelope(written.envelope, current.envelope);
}

bool _sameEnvelope(CryptoEnvelope? a, CryptoEnvelope? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null) return false;
  return a.conversationId == b.conversationId &&
      a.senderDeviceId == b.senderDeviceId &&
      a.ciphertext == b.ciphertext &&
      a.nonce == b.nonce &&
      a.version == b.version &&
      a.messageKind == b.messageKind &&
      identical(a.attachment, b.attachment);
}

bool _sameSession(ConversationSessionState? a, ConversationSessionState? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null) return false;
  return a.sessionLocator == b.sessionLocator &&
      a.sessionEnvelopeVersion == b.sessionEnvelopeVersion &&
      a.requiresLocalPersistence == b.requiresLocalPersistence &&
      a.sessionSchemaVersion == b.sessionSchemaVersion &&
      a.localDeviceId == b.localDeviceId &&
      a.remoteDeviceId == b.remoteDeviceId &&
      a.remoteIdentityFingerprint == b.remoteIdentityFingerprint &&
      a.bootstrappedAt == b.bootstrappedAt &&
      a.auditHint == b.auditHint &&
      a.remoteIdentityPublicKey == b.remoteIdentityPublicKey;
}
