import 'dart:math' as math;

import '../../../../core/storage/conversation_cache_service.dart';
import 'messenger_persistence.dart';

/// The outbox's queued messages, in memory and in the cache, shared by the
/// outbox and the attachment uploads that prepare them.
///
/// A message the user cancelled stays cancelled: [save] and [put] ignore it
/// from then on, so an upload or a send still settling cannot write it back
/// after [cancel] (which is what would bring it back as "Not sent").
///
/// It also hands out the queue numbers (PendingMessageRecord.queueOrder):
/// one counter for the process, never lowered, so every message queued
/// after a restart stands behind every message restored from the cache.
class PendingMessages {
  PendingMessages(this._persistence);

  final MessengerPersistence _persistence;
  final Map<String, PendingMessageRecord> _records = {};
  final Set<String> _canceled = {};
  // The next queue number to hand out: one for the process, so a queue
  // rebuilt in the same run (a new sign-in, a new controller) never hands
  // out a number again.
  static int _next = 1;

  PendingMessageRecord? operator [](String clientMessageId) => _records[clientMessageId];

  /// Every queued message the user has not cancelled.
  Iterable<PendingMessageRecord> get all =>
      _records.values.where((record) => !_canceled.contains(record.clientMessageId));

  bool get isEmpty => all.isEmpty;

  /// Whether the user cancelled [clientMessageId].
  bool isCanceled(String clientMessageId) => _canceled.contains(clientMessageId);

  /// Marks [clientMessageId] cancelled; its record stays until [remove].
  void cancel(String clientMessageId) => _canceled.add(clientMessageId);

  /// The queue number for the message queued next, above every number
  /// handed out or restored so far.
  int nextQueueOrder() => _next++;

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

  /// Drops [clientMessageId] and deletes its cache row, with nothing to
  /// write first: a record that nothing takes the place of.
  Future<void> drop(String clientMessageId) {
    _records.remove(clientMessageId);
    return _persistence.removePending(clientMessageId);
  }

  /// Replaces everything with the records the cache held. The next queue
  /// number moves above every restored one; it never moves down.
  void restore(Iterable<PendingMessageRecord> records) {
    _records
      ..clear()
      ..addAll({for (final record in records) record.clientMessageId: record});
    for (final record in _records.values) {
      _next = math.max(_next, record.queueOrder + 1);
    }
  }

  /// Forgets every record; the numbers handed out so far stay handed out.
  void clear() {
    _records.clear();
    _canceled.clear();
  }
}
