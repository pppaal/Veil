import '../../../../core/storage/conversation_cache_service.dart';

/// Content store used when the configured cache cannot persist content
/// (no database yet, or a test fake). Same contract as the Drift store, but
/// it only lives as long as the process.
class InMemoryMessageContentStore implements MessageContentStore {
  final Map<String, MessageContentRecord> _records = {};

  @override
  Future<void> put(MessageContentRecord record) async {
    _records[record.messageKey] = record;
  }

  @override
  Future<MessageContentRecord?> get(String messageKey) async => _records[messageKey];

  @override
  Future<Map<String, MessageContentRecord>> getMany(Iterable<String> messageKeys) async {
    return {
      for (final key in messageKeys)
        if (_records[key] case final record?) key: record,
    };
  }

  @override
  Future<void> rekeyLocalToServer({
    required String clientMessageId,
    required String serverMessageId,
  }) async {
    final local = _records.remove(localMessageContentKey(clientMessageId));
    if (local == null) {
      return;
    }
    _records[serverMessageId] = MessageContentRecord(
      messageKey: serverMessageId,
      conversationId: local.conversationId,
      clientMessageId: local.clientMessageId,
      serverMessageId: serverMessageId,
      body: local.body,
      kind: local.kind,
      attachment: local.attachment,
      innerExpiresAt: local.innerExpiresAt,
      status: local.status,
      createdAt: local.createdAt,
      updatedAt: DateTime.now(),
    );
  }

  @override
  Future<void> deleteConversation(String conversationId) async {
    _records.removeWhere((_, record) => record.conversationId == conversationId);
  }

  @override
  Future<void> deleteExpired(
    DateTime now, {
    Iterable<String> messageKeys = const [],
  }) async {
    _records.removeWhere((_, record) {
      final expiresAt = record.innerExpiresAt;
      return expiresAt != null && !expiresAt.isAfter(now);
    });
    messageKeys.forEach(_records.remove);
  }

  void clear() => _records.clear();
}
