import '../../../../core/storage/conversation_cache_service.dart';
import 'messenger_persistence.dart';

/// The outbox's queued messages, in memory and in the cache, shared by the
/// outbox and the attachment uploads that prepare them.
class PendingMessages {
  PendingMessages(this._persistence);

  final MessengerPersistence _persistence;
  final Map<String, PendingMessageRecord> _records = {};

  PendingMessageRecord? operator [](String clientMessageId) => _records[clientMessageId];

  Iterable<PendingMessageRecord> get all => _records.values;

  bool get isEmpty => _records.isEmpty;

  /// Keeps [record] and writes it to the cache.
  Future<void> save(PendingMessageRecord record) {
    _records[record.clientMessageId] = record;
    return _persistence.savePending(record);
  }

  /// Keeps [record] in memory only, for changes not worth a write each.
  void put(PendingMessageRecord record) => _records[record.clientMessageId] = record;

  /// Drops [clientMessageId]. Its cache row is deleted only after the
  /// state's unwritten changes are written, so the message that takes its
  /// place (the relayed copy, its conversation and the session it opened)
  /// is in the cache first: a crash in between leaves it in one or the
  /// other, never in neither.
  Future<void> remove(String clientMessageId) async {
    _records.remove(clientMessageId);
    await _persistence.flush();
    await _persistence.removePending(clientMessageId);
  }

  /// Replaces everything with the records the cache held.
  void restore(Iterable<PendingMessageRecord> records) {
    _records
      ..clear()
      ..addAll({for (final record in records) record.clientMessageId: record});
  }

  void clear() => _records.clear();
}
