import 'dart:async';

import '../domain/chat_message.dart';
import '../domain/conversation_preview.dart';
import '../domain/message_search.dart';
import 'conversation_cache_service.dart';
import 'in_memory_message_content_store.dart';

/// A stable stand-in for the encrypted conversation cache, whose database
/// opens asynchronously and is reopened after a wipe.
///
/// Consumers hold the handle for their whole life, so nothing is rebuilt
/// when the database becomes ready. Every call waits for the current cache:
/// content decrypted before the database opened would otherwise land in a
/// throwaway in-memory store, and its single-use message keys would be
/// spent for nothing.
///
/// A database that cannot be opened leaves the app as it runs without a
/// local cache: nothing is kept beyond the process, but messaging, sign-out
/// and wipe keep working. Each call tries the database again. Only the
/// row-level calls of a writer that records what it wrote throw instead
/// ([ConversationCacheUnavailable]), so it never counts a write that
/// reached no database.
///
/// The session controller wipes the cache through the same handle the
/// messenger writes through, so a wipe waits for every write already under
/// way: one that began before the wipe lands before it, never after.
class CacheHandle implements ConversationCacheService, MessageContentStore, IncrementalConversationCache {
  CacheHandle(this._resolve);

  /// Returns the cache that is current at the time of the call; throws when
  /// its database cannot be opened.
  final Future<DriftConversationCacheService> Function() _resolve;
  final InMemoryMessageContentStore _processOnlyContent = InMemoryMessageContentStore();
  final Set<Future<void>> _writing = {};
  int _wipes = 0;

  @override
  int get wipes => _wipes;

  Future<DriftConversationCacheService?> _cache() async {
    try {
      return await _resolve();
    } catch (_) {
      return null;
    }
  }

  Future<DriftConversationCacheService> _requireCache() async {
    try {
      return await _resolve();
    } catch (error) {
      throw ConversationCacheUnavailable(error);
    }
  }

  // Starts [write] as one the next wipe waits for. Every mutating call
  // goes through here before its first await, so no write can begin
  // unseen by a wipe that starts after it.
  Future<void> _write(Future<void> Function() write) {
    final result = write();
    final settled = result.then<void>((_) {}, onError: (Object _) {});
    _writing.add(settled);
    unawaited(settled.whenComplete(() => _writing.remove(settled)));
    return result;
  }

  Future<MessageContentStore> _contents() async => await _cache() ?? _processOnlyContent;

  @override
  Future<List<ConversationPreview>> readConversations() async =>
      await (await _cache())?.readConversations() ?? const [];

  @override
  Future<List<ChatMessage>> readMessages(String conversationId) async =>
      await (await _cache())?.readMessages(conversationId) ?? const [];

  @override
  Future<void> storeConversations(List<ConversationPreview> conversations) =>
      _write(() async => (await _cache())?.storeConversations(conversations));

  @override
  Future<void> storeMessages(String conversationId, List<ChatMessage> messages) =>
      _write(() async => (await _cache())?.storeMessages(conversationId, messages));

  @override
  Future<ConversationPagingState> readPagingState(String conversationId) async =>
      await (await _cache())?.readPagingState(conversationId) ?? const ConversationPagingState();

  @override
  Future<void> storePagingState(
    String conversationId, {
    String? nextCursor,
    required bool hasMoreHistory,
    DateTime? lastSyncedAt,
  }) =>
      _write(() async => (await _cache())?.storePagingState(
            conversationId,
            nextCursor: nextCursor,
            hasMoreHistory: hasMoreHistory,
            lastSyncedAt: lastSyncedAt,
          ));

  @override
  Future<List<PendingMessageRecord>> readPendingMessages() async =>
      await (await _cache())?.readPendingMessages() ?? const [];

  @override
  Future<void> upsertPendingMessage(PendingMessageRecord pending) =>
      _write(() async => (await _cache())?.upsertPendingMessage(pending));

  @override
  Future<void> removePendingMessage(String clientMessageId) =>
      _write(() async => (await _cache())?.removePendingMessage(clientMessageId));

  @override
  Future<void> indexMessageBody({
    required String conversationId,
    required String messageId,
    required String searchableBody,
  }) =>
      _write(() async => (await _cache())?.indexMessageBody(
            conversationId: conversationId,
            messageId: messageId,
            searchableBody: searchableBody,
          ));

  @override
  Future<List<String>> searchCachedMessageIds({
    required String conversationId,
    required String query,
  }) async =>
      await (await _cache())?.searchCachedMessageIds(conversationId: conversationId, query: query) ?? const [];

  @override
  Future<MessageSearchPage> searchMessageArchive({
    required MessageSearchQuery query,
    required String currentDeviceId,
  }) async =>
      await (await _cache())?.searchMessageArchive(query: query, currentDeviceId: currentDeviceId) ??
      const MessageSearchPage(items: <MessageSearchResult>[]);

  @override
  Future<ConversationCacheSnapshot> readSnapshot() async => (await _requireCache()).readSnapshot();

  @override
  Future<void> writeChanges(ConversationCacheChanges changes) =>
      _write(() async => (await _requireCache()).writeChanges(changes));

  @override
  Future<void> purgeExpiredMessages({DateTime? now}) =>
      _write(() async => (await _cache())?.purgeExpiredMessages(now: now));

  @override
  Future<void> clearAll() async {
    _wipes += 1;
    await Future.wait([..._writing]);
    _processOnlyContent.clear();
    await (await _cache())?.clearAll();
  }

  @override
  Future<void> put(MessageContentRecord record) => _write(() async => (await _contents()).put(record));

  @override
  Future<MessageContentRecord?> get(String messageKey) async => (await _contents()).get(messageKey);

  @override
  Future<Map<String, MessageContentRecord>> getMany(Iterable<String> messageKeys) async =>
      (await _contents()).getMany(messageKeys);

  @override
  Future<Map<String, DateTime>> innerExpiries(Iterable<String> messageKeys) async =>
      (await _contents()).innerExpiries(messageKeys);

  @override
  Future<void> rekeyLocalToServer({
    required String clientMessageId,
    required String serverMessageId,
  }) =>
      _write(() async => (await _contents())
          .rekeyLocalToServer(clientMessageId: clientMessageId, serverMessageId: serverMessageId));

  @override
  Future<void> deleteConversation(String conversationId) =>
      _write(() async => (await _contents()).deleteConversation(conversationId));

  @override
  Future<void> deleteExpired(DateTime now, {Iterable<String> messageKeys = const []}) =>
      _write(() async => (await _contents()).deleteExpired(now, messageKeys: messageKeys));

  @override
  Future<Set<String>> retiredAmong(Iterable<String> messageKeys) async =>
      (await _contents()).retiredAmong(messageKeys);
}
