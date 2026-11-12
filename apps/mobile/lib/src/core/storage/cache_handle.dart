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
/// and wipe keep working. Each call tries the database again.
class CacheHandle implements ConversationCacheService, MessageContentStore, IncrementalConversationCache {
  CacheHandle(this._resolve);

  /// Returns the cache that is current at the time of the call; throws when
  /// its database cannot be opened.
  final Future<DriftConversationCacheService> Function() _resolve;
  final InMemoryMessageContentStore _processOnlyContent = InMemoryMessageContentStore();

  Future<DriftConversationCacheService?> _cache() async {
    try {
      return await _resolve();
    } catch (_) {
      return null;
    }
  }

  Future<MessageContentStore> _contents() async => await _cache() ?? _processOnlyContent;

  @override
  Future<List<ConversationPreview>> readConversations() async =>
      await (await _cache())?.readConversations() ?? const [];

  @override
  Future<List<ChatMessage>> readMessages(String conversationId) async =>
      await (await _cache())?.readMessages(conversationId) ?? const [];

  @override
  Future<void> storeConversations(List<ConversationPreview> conversations) async =>
      (await _cache())?.storeConversations(conversations);

  @override
  Future<void> storeMessages(String conversationId, List<ChatMessage> messages) async =>
      (await _cache())?.storeMessages(conversationId, messages);

  @override
  Future<ConversationPagingState> readPagingState(String conversationId) async =>
      await (await _cache())?.readPagingState(conversationId) ?? const ConversationPagingState();

  @override
  Future<void> storePagingState(
    String conversationId, {
    String? nextCursor,
    required bool hasMoreHistory,
    DateTime? lastSyncedAt,
  }) async =>
      (await _cache())?.storePagingState(
        conversationId,
        nextCursor: nextCursor,
        hasMoreHistory: hasMoreHistory,
        lastSyncedAt: lastSyncedAt,
      );

  @override
  Future<List<PendingMessageRecord>> readPendingMessages() async =>
      await (await _cache())?.readPendingMessages() ?? const [];

  @override
  Future<void> upsertPendingMessage(PendingMessageRecord pending) async =>
      (await _cache())?.upsertPendingMessage(pending);

  @override
  Future<void> removePendingMessage(String clientMessageId) async =>
      (await _cache())?.removePendingMessage(clientMessageId);

  @override
  Future<void> indexMessageBody({
    required String conversationId,
    required String messageId,
    required String searchableBody,
  }) async =>
      (await _cache())?.indexMessageBody(
        conversationId: conversationId,
        messageId: messageId,
        searchableBody: searchableBody,
      );

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
  Future<ConversationCacheSnapshot> readSnapshot() async =>
      await (await _cache())?.readSnapshot() ?? const ConversationCacheSnapshot();

  @override
  Future<void> writeChanges(ConversationCacheChanges changes) async => (await _cache())?.writeChanges(changes);

  @override
  Future<void> purgeExpiredMessages() async => (await _cache())?.purgeExpiredMessages();

  @override
  Future<void> clearAll() async {
    _processOnlyContent.clear();
    await (await _cache())?.clearAll();
  }

  @override
  Future<void> put(MessageContentRecord record) async => (await _contents()).put(record);

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
  }) async =>
      (await _contents()).rekeyLocalToServer(clientMessageId: clientMessageId, serverMessageId: serverMessageId);

  @override
  Future<void> deleteConversation(String conversationId) async =>
      (await _contents()).deleteConversation(conversationId);

  @override
  Future<void> deleteExpired(DateTime now, {Iterable<String> messageKeys = const []}) async =>
      (await _contents()).deleteExpired(now, messageKeys: messageKeys);

  @override
  Future<Set<String>> retiredAmong(Iterable<String> messageKeys) async =>
      (await _contents()).retiredAmong(messageKeys);
}
