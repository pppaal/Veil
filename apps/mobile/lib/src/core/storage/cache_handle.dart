import '../../features/conversations/data/conversation_models.dart';
import 'conversation_cache_service.dart';

/// A stable stand-in for the encrypted conversation cache, whose database
/// opens asynchronously and is reopened after a wipe.
///
/// Consumers hold the handle for their whole life, so nothing is rebuilt
/// when the database becomes ready. Every call waits for the current cache:
/// content decrypted before the database opened would otherwise land in a
/// throwaway in-memory store, and its single-use message keys would be
/// spent for nothing.
class CacheHandle implements ConversationCacheService, MessageContentStore {
  CacheHandle(this._resolve);

  /// Returns the cache that is current at the time of the call.
  final Future<DriftConversationCacheService> Function() _resolve;

  @override
  Future<List<ConversationPreview>> readConversations() async => (await _resolve()).readConversations();

  @override
  Future<List<ChatMessage>> readMessages(String conversationId) async =>
      (await _resolve()).readMessages(conversationId);

  @override
  Future<void> storeConversations(List<ConversationPreview> conversations) async =>
      (await _resolve()).storeConversations(conversations);

  @override
  Future<void> storeMessages(String conversationId, List<ChatMessage> messages) async =>
      (await _resolve()).storeMessages(conversationId, messages);

  @override
  Future<ConversationPagingState> readPagingState(String conversationId) async =>
      (await _resolve()).readPagingState(conversationId);

  @override
  Future<void> storePagingState(
    String conversationId, {
    String? nextCursor,
    required bool hasMoreHistory,
    DateTime? lastSyncedAt,
  }) async =>
      (await _resolve()).storePagingState(
        conversationId,
        nextCursor: nextCursor,
        hasMoreHistory: hasMoreHistory,
        lastSyncedAt: lastSyncedAt,
      );

  @override
  Future<List<PendingMessageRecord>> readPendingMessages() async => (await _resolve()).readPendingMessages();

  @override
  Future<void> upsertPendingMessage(PendingMessageRecord pending) async =>
      (await _resolve()).upsertPendingMessage(pending);

  @override
  Future<void> removePendingMessage(String clientMessageId) async =>
      (await _resolve()).removePendingMessage(clientMessageId);

  @override
  Future<void> indexMessageBody({
    required String conversationId,
    required String messageId,
    required String searchableBody,
  }) async =>
      (await _resolve()).indexMessageBody(
        conversationId: conversationId,
        messageId: messageId,
        searchableBody: searchableBody,
      );

  @override
  Future<List<String>> searchCachedMessageIds({
    required String conversationId,
    required String query,
  }) async =>
      (await _resolve()).searchCachedMessageIds(conversationId: conversationId, query: query);

  @override
  Future<MessageSearchPage> searchMessageArchive({
    required MessageSearchQuery query,
    required String currentDeviceId,
  }) async =>
      (await _resolve()).searchMessageArchive(query: query, currentDeviceId: currentDeviceId);

  @override
  Future<void> purgeExpiredMessages() async => (await _resolve()).purgeExpiredMessages();

  @override
  Future<void> clearAll() async => (await _resolve()).clearAll();

  @override
  Future<void> put(MessageContentRecord record) async => (await _resolve()).put(record);

  @override
  Future<MessageContentRecord?> get(String messageKey) async => (await _resolve()).get(messageKey);

  @override
  Future<Map<String, MessageContentRecord>> getMany(Iterable<String> messageKeys) async =>
      (await _resolve()).getMany(messageKeys);

  @override
  Future<Map<String, DateTime>> innerExpiries(Iterable<String> messageKeys) async =>
      (await _resolve()).innerExpiries(messageKeys);

  @override
  Future<void> rekeyLocalToServer({
    required String clientMessageId,
    required String serverMessageId,
  }) async =>
      (await _resolve()).rekeyLocalToServer(clientMessageId: clientMessageId, serverMessageId: serverMessageId);

  @override
  Future<void> deleteConversation(String conversationId) async =>
      (await _resolve()).deleteConversation(conversationId);

  @override
  Future<void> deleteExpired(DateTime now, {Iterable<String> messageKeys = const []}) async =>
      (await _resolve()).deleteExpired(now, messageKeys: messageKeys);

  @override
  Future<Set<String>> retiredAmong(Iterable<String> messageKeys) async =>
      (await _resolve()).retiredAmong(messageKeys);
}
