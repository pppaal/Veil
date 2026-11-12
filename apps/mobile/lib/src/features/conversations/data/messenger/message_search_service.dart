import '../../../../core/storage/conversation_cache_service.dart';
import '../conversation_models.dart';
import 'message_content_service.dart';
import 'messenger_session_context.dart';
import 'messenger_state_store.dart';

/// Search over decrypted content kept on this device. It reads stored
/// content only and never decrypts, so searching spends no message key.
class MessageSearchService {
  MessageSearchService({
    required MessengerStateStore store,
    required MessageContentService contents,
    required ConversationCacheService? cache,
    required MessengerSessionContext session,
  })  : _store = store,
        _contents = contents,
        _cache = cache,
        _session = session;

  final MessengerStateStore _store;
  final MessageContentService _contents;
  final ConversationCacheService? _cache;
  final MessengerSessionContext _session;

  /// Ids of the loaded messages of [conversationId] whose content matches
  /// [query]; every loaded id for an empty query.
  Future<List<String>> searchLoaded(String conversationId, {required String query}) async {
    final messages = _store.messagesOf(conversationId);
    final normalizedQuery = _normalize(query);
    if (normalizedQuery.isEmpty) {
      return messages.map((message) => message.id).toList();
    }

    final contents = await _contents.storedFor(messages);
    return [
      for (final message in messages)
        if (contents[message.id] case final content?
            when content.status == MessageContentStatus.ok &&
                searchableContentText(content).toLowerCase().contains(normalizedQuery))
          message.id,
    ];
  }

  /// A page of matches across every cached conversation.
  Future<MessageSearchPage> searchArchive(MessageSearchQuery query) async {
    final normalizedQuery = _normalize(query.query);
    final cache = _cache;
    final deviceId = _session.deviceId;
    if (normalizedQuery.isEmpty || cache == null || deviceId == null) {
      return const MessageSearchPage(items: <MessageSearchResult>[]);
    }

    return cache.searchMessageArchive(
      query: MessageSearchQuery(
        query: normalizedQuery,
        conversationId: query.conversationId,
        senderFilter: query.senderFilter,
        typeFilter: query.typeFilter,
        dateFilter: query.dateFilter,
        limit: query.limit,
        beforeSentAt: query.beforeSentAt,
        beforeMessageId: query.beforeMessageId,
      ),
      currentDeviceId: deviceId,
    );
  }

  static String _normalize(String value) => value.trim().toLowerCase();
}
