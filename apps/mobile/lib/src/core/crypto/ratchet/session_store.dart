import 'dart:async';
import 'dart:math';

import 'ratchet_state.dart';
import 'session_lock.dart';
import 'session_record.dart';

/// Callback that makes a conversation's session record durable. It must
/// complete only once the snapshot is written: callers rely on that to never
/// hand out ciphertext whose ratchet state could be lost in a crash.
typedef SessionPersister = Future<void> Function(String conversationId, Map<String, dynamic> snapshot);

/// In-memory session records with copy-on-write commits.
///
/// A commit persists the new record first and publishes it second, so
/// memory never runs ahead of disk: a crash replays from the last durable
/// state, and a failed write leaves the previous state live.
class SessionRecordStore {
  SessionRecordStore({required DateTime Function() clock}) : _clock = clock;

  final DateTime Function() _clock;
  final Map<String, SessionRecord> _records = {};
  // Highest rev storage reported per conversation, including snapshots that
  // failed to parse: a record re-created over one must still outrank it.
  final Map<String, int> _storedRevs = {};
  final SessionLock _lock = SessionLock();
  final Set<Future<void>> _inflightWrites = {};

  SessionPersister? persister;

  SessionRecord? operator [](String conversationId) => _records[conversationId];

  bool contains(String conversationId) => _records.containsKey(conversationId);

  Future<T> serialized<T>(String conversationId, Future<T> Function() action) =>
      _lock.synchronized(conversationId, action);

  /// Must run inside [serialized] for the same conversation.
  Future<void> commit(String conversationId, RecordUpdate update) async {
    final previousRev = max(_records[conversationId]?.rev ?? 0, _storedRevs[conversationId] ?? 0);
    // The clock seed keeps a record created before its snapshot was ever
    // restored above the stored rev in the common case; storage refuses the
    // write in the rare one where the clock went backwards.
    final rev = max(previousRev + 1, _clock().microsecondsSinceEpoch);
    final record = update.record.withRev(rev);
    final persister = this.persister;
    if (persister != null) {
      final write = persister(conversationId, record.toSnapshot());
      _inflightWrites.add(write);
      try {
        await write;
      } finally {
        _inflightWrites.remove(write);
      }
    }
    _records[conversationId] = record;
    for (final state in update.superseded) {
      state.destroy();
    }
  }

  /// Rehydrates a persisted record unless memory already holds a newer one.
  Future<void> restore(String conversationId, Map<String, dynamic> snapshot) => serialized(conversationId, () async {
        final storedRev = snapshot['rev'];
        if (storedRev is int) _storedRevs[conversationId] = max(storedRev, _storedRevs[conversationId] ?? 0);
        final restored = SessionRecord.fromSnapshot(snapshot, now: _clock());
        if (restored == null) return;
        final existing = _records[conversationId];
        if (existing != null && existing.rev >= restored.rev) {
          restored.states.forEach(_destroy);
          return;
        }
        _records[conversationId] = restored;
        existing?.states.forEach(_destroy);
      });

  /// Waits for every snapshot write that is still in progress. A failed
  /// write already surfaced to the operation that issued it.
  Future<void> flush() async {
    while (_inflightWrites.isNotEmpty) {
      await Future.wait([
        for (final write in List<Future<void>>.of(_inflightWrites)) write.then((_) {}, onError: (Object _) {}),
      ]);
    }
  }

  static void _destroy(RatchetState state) => state.destroy();
}
