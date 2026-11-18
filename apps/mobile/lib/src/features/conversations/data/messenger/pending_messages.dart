import '../../../../core/storage/conversation_cache_service.dart';
import 'messenger_persistence.dart';

/// The outbox's queued messages, in memory and in the cache, shared by the
/// outbox and the attachment uploads that prepare them.
///
/// A message the user cancelled stays cancelled: [save] and [put] ignore it
/// from then on, so an upload or a send still settling cannot write it back
/// after [cancel] (which is what would bring it back as "Not sent").
class PendingMessages {
  PendingMessages(this._persistence);

  final MessengerPersistence _persistence;
  final Map<String, PendingMessageRecord> _records = {};
  final Set<String> _canceled = {};

  PendingMessageRecord? operator [](String clientMessageId) => _records[clientMessageId];

  /// Every queued message the user has not cancelled.
  Iterable<PendingMessageRecord> get all =>
      _records.values.where((record) => !_canceled.contains(record.clientMessageId));

  bool get isEmpty => all.isEmpty;

  /// Whether the user cancelled [clientMessageId].
  bool isCanceled(String clientMessageId) => _canceled.contains(clientMessageId);

  /// Marks [clientMessageId] cancelled; its record stays until [remove].
  void cancel(String clientMessageId) => _canceled.add(clientMessageId);

  /// Keeps [record] and writes it to the cache, unless it was cancelled.
  Future<void> save(PendingMessageRecord record) {
    if (_canceled.contains(record.clientMessageId)) return Future<void>.value();
    _records[record.clientMessageId] = record;
    return _persistence.savePending(record);
  }

  /// Keeps [record] in memory only, for changes not worth a write each.
  void put(PendingMessageRecord record) {
    if (_canceled.contains(record.clientMessageId)) return;
    _records[record.clientMessageId] = record;
  }

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

  void clear() {
    _records.clear();
    _canceled.clear();
  }
}
