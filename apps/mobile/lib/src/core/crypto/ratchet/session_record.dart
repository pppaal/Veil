/// All ratchet states for one conversation: the state we send on plus
/// archived states that may still receive in-flight messages (re-bootstrap,
/// glare, a peer that re-initiated).
///
/// Persisted as snapshot schema v4: `{v: 4, rev, current, archived[]}`.
/// `rev` only grows, so storage can refuse a write that lost a race.
library;

import '../bytes.dart';
import 'ratchet_state.dart';

const int sessionSnapshotSchemaVersion = 4;
const int maxArchivedStates = 5;
const Duration archivedStateRetention = Duration(days: 30);

class ArchivedState {
  ArchivedState(this.state, this.archivedAt);

  final RatchetState state;
  final DateTime archivedAt;
}

/// A record to commit plus the states it displaced. The displaced states
/// are destroyed only after the commit is durable.
class RecordUpdate {
  RecordUpdate(this.record, [this.superseded = const []]);

  final SessionRecord record;
  final List<RatchetState> superseded;
}

class SessionRecord {
  SessionRecord({required this.rev, required this.current, List<ArchivedState> archived = const []})
      : archived = List.unmodifiable(archived);

  final int rev;
  final RatchetState current;
  final List<ArchivedState> archived;

  Iterable<RatchetState> get states sync* {
    yield current;
    for (final entry in archived) {
      yield entry.state;
    }
  }

  SessionRecord withRev(int rev) => SessionRecord(rev: rev, current: current, archived: archived);

  /// Swaps [live] for its updated copy, wherever it sits in the record.
  RecordUpdate replacing(RatchetState live, RatchetState replacement, {required DateTime now}) {
    if (identical(live, current)) {
      return _pruned(replacement, archived, [live], now);
    }
    final next = [
      for (final entry in archived) identical(entry.state, live) ? ArchivedState(replacement, entry.archivedAt) : entry,
    ];
    return _pruned(current, next, [live], now);
  }

  /// [state] becomes the sending state; the old one is archived, never
  /// destroyed, so messages already in flight on it still decrypt.
  RecordUpdate promoting(RatchetState state, {required DateTime now}) =>
      _pruned(state, [ArchivedState(current, now), ...archived], const [], now);

  RecordUpdate archiving(RatchetState state, {required DateTime now}) =>
      _pruned(current, [ArchivedState(state, now), ...archived], const [], now);

  /// Installs a state a peer just opened with a PreKey frame. In glare (we
  /// initiated too and have not heard back), both peers keep the state whose
  /// initiator has the lexicographically lower identity key, so they
  /// converge on one sending state; the other remains decryptable.
  static RecordUpdate installingInbound(SessionRecord? record, RatchetState incoming, {required DateTime now}) {
    if (record == null) return RecordUpdate(SessionRecord(rev: 0, current: incoming));
    final current = record.current;
    final ownKey = current.localIdentityKey;
    final peerKey = incoming.remoteIdentityKey;
    final ourPendingInitiationWins = current.initiatedLocally &&
        current.awaitingFirstReply &&
        ownKey != null &&
        peerKey != null &&
        compareBytes(ownKey, peerKey) < 0;
    return ourPendingInitiationWins ? record.archiving(incoming, now: now) : record.promoting(incoming, now: now);
  }

  RecordUpdate _pruned(
    RatchetState nextCurrent,
    List<ArchivedState> nextArchived,
    List<RatchetState> superseded,
    DateTime now,
  ) {
    final cutoff = now.subtract(archivedStateRetention);
    final kept = <ArchivedState>[];
    final dropped = <RatchetState>[...superseded];
    for (final entry in nextArchived) {
      if (kept.length < maxArchivedStates && !entry.archivedAt.isBefore(cutoff)) {
        kept.add(entry);
      } else {
        dropped.add(entry.state);
      }
    }
    return RecordUpdate(SessionRecord(rev: rev, current: nextCurrent, archived: kept), dropped);
  }

  Map<String, dynamic> toSnapshot() => {
        'v': sessionSnapshotSchemaVersion,
        'rev': rev,
        'current': current.toJson(),
        'archived': [
          for (final entry in archived)
            {'archivedAt': entry.archivedAt.toUtc().toIso8601String(), 'state': entry.state.toJson()},
        ],
      };

  /// Reads a v4 snapshot, or wraps a v2/v3 single-state snapshot as the
  /// current state of a fresh record. Unknown or corrupt input yields null so
  /// the caller re-bootstraps instead of crashing.
  static SessionRecord? fromSnapshot(Map<String, dynamic> json, {required DateTime now}) {
    try {
      final version = (json['v'] as num?)?.toInt() ?? 0;
      if (version == 2 || version == 3) {
        return SessionRecord(rev: 0, current: RatchetState.fromJson(json, now: now));
      }
      if (version != sessionSnapshotSchemaVersion) return null;
      return SessionRecord(
        rev: (json['rev'] as num).toInt(),
        current: RatchetState.fromJson(json['current'] as Map<String, dynamic>, now: now),
        archived: [
          for (final raw in json['archived'] as List<dynamic>? ?? const [])
            ArchivedState(
              RatchetState.fromJson((raw as Map<String, dynamic>)['state'] as Map<String, dynamic>, now: now),
              DateTime.parse(raw['archivedAt'] as String).toUtc(),
            ),
        ],
      );
    } catch (_) {
      return null;
    }
  }
}
