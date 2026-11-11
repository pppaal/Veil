import '../../../../core/storage/conversation_cache_service.dart';

/// Content store used when the configured cache cannot persist content
/// (no database yet, or a test fake). Same contract as the Drift store, but
/// it only lives as long as the process.
class InMemoryMessageContentStore implements MessageContentStore {
  final Map<String, MessageContentRecord> _records = {};
  final Set<String> _retired = {};

  @override
  Future<void> put(MessageContentRecord record) async {
    if (!_retired.contains(record.messageKey)) {
      _records[record.messageKey] = record;
    }
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
  Future<Map<String, DateTime>> innerExpiries(Iterable<String> messageKeys) async {
    return {
      for (final key in messageKeys)
        if (_records[key]?.innerExpiresAt case final expiresAt?) key: expiresAt,
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
    final innerExpired = [
      for (final record in _records.values)
        if (record.innerExpiresAt case final expiresAt? when !expiresAt.isAfter(now)) record.messageKey,
    ];
    for (final key in [...innerExpired, ...messageKeys]) {
      _records.remove(key);
      _retired.add(key);
    }
  }

  @override
  Future<Set<String>> retiredAmong(Iterable<String> messageKeys) async =>
      messageKeys.where(_retired.contains).toSet();

  void clear() {
    _records.clear();
    _retired.clear();
  }
}
