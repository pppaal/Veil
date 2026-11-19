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
// Counted from an archived state's last use, so a state the peer still sends
// on is never dropped while it is in use.
const Duration archivedStateRetention = Duration(days: 30);

class ArchivedState {
  ArchivedState(this.state, this.lastUsedAt);

  final RatchetState state;
  // When the state was archived or last committed, whichever is later.
  final DateTime lastUsedAt;
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
  // Most recently used first, so the count cap drops the stalest state.
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
    return _pruned(current, [ArchivedState(replacement, now), ..._archivedExcept(live)], [live], now);
  }

  /// Commits [replacement], the copy of [live] that just authenticated a
  /// received message. A peer sends on the state it last chose, so an
  /// archived state that receives becomes the sending state as well
  /// (Signal's promoteState): each side ends up sending on the state its
  /// peer last used, which converges whatever order frames arrive in.
  RecordUpdate receiving(RatchetState live, RatchetState replacement, {required DateTime now}) {
    if (identical(live, current) || !(_mayDisplaceCurrent(replacement) || _peerAbandonedOurs(live))) {
      return replacing(live, replacement, now: now);
    }
    return _pruned(replacement, [ArchivedState(current, now), ..._archivedExcept(live)], [live], now);
  }

  /// [state] becomes the sending state; the old one is archived, never
  /// destroyed, so messages already in flight on it still decrypt.
  RecordUpdate promoting(RatchetState state, {required DateTime now}) =>
      _pruned(state, [ArchivedState(current, now), ...archived], const [], now);

  RecordUpdate archiving(RatchetState state, {required DateTime now}) =>
      _pruned(current, [ArchivedState(state, now), ...archived], const [], now);

  /// Installs a state a peer just opened with a PreKey frame. It is the
  /// peer's newest handshake, so it becomes the sending state unless it
  /// competes with our own unanswered initiation and loses the glare
  /// tie-break.
  static RecordUpdate installingInbound(SessionRecord? record, RatchetState incoming, {required DateTime now}) {
    if (record == null) return RecordUpdate(SessionRecord(rev: 0, current: incoming));
    final current = record.current;
    return current.initiatedLocally && _handshakeHolds(current, incoming)
        ? record.archiving(incoming, now: now)
        : record.promoting(incoming, now: now);
  }

  // Never across protocols or identities: a legacy state would downgrade the
  // conversation, and a state bound to another identity must not win the
  // sending role back just because it still receives.
  bool _mayDisplaceCurrent(RatchetState candidate) {
    final currentPeer = current.remoteIdentityKey;
    final candidatePeer = candidate.remoteIdentityKey;
    return current.protocol == protocolV2 &&
        candidate.protocol == protocolV2 &&
        currentPeer != null &&
        candidatePeer != null &&
        compareBytes(currentPeer, candidatePeer) == 0 &&
        !_handshakeHolds(current, candidate);
  }

  /// Our initiation is still unanswered while the peer sends a further frame
  /// on a handshake of its own that we never answered. A peer that holds our
  /// handshake would not keep sending on its own, so it did not take ours,
  /// typically because it could not open it (the one-time or signed prekey
  /// it names is gone): holding on to ours would leave every message we send
  /// unreadable for good. The first competing frame ([live] has received
  /// nothing yet) still loses glare as specified, so true glare settles as
  /// before, and a state we already sent on never qualifies.
  bool _peerAbandonedOurs(RatchetState live) {
    final ours = current.remoteIdentityKey;
    final theirs = live.remoteIdentityKey;
    return current.protocol == protocolV2 &&
        current.initiatedLocally &&
        current.awaitingFirstReply &&
        live.protocol == protocolV2 &&
        !live.initiatedLocally &&
        live.handshakePending &&
        live.receiveCounter > 0 &&
        ours != null &&
        theirs != null &&
        compareBytes(ours, theirs) == 0;
  }

  /// Glare tie-break. While [current]'s handshake is pending (our initiation
  /// the peer has not answered, or the peer's that we have not answered),
  /// the peer may not have seen it yet, so its traffic on [competitor] does
  /// not show which state it settled on. [current] therefore holds unless
  /// [competitor] was initiated by the party with the bytewise lower
  /// identity key: the comparison the peer applies to the same two
  /// handshakes, so both settle on one.
  static bool _handshakeHolds(RatchetState current, RatchetState competitor) {
    if (!current.handshakePending) return false;
    final held = current.initiatorIdentityKey;
    final challenger = competitor.initiatorIdentityKey;
    return held != null && challenger != null && compareBytes(challenger, held) >= 0;
  }

  Iterable<ArchivedState> _archivedExcept(RatchetState state) => archived.where((e) => !identical(e.state, state));

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
      if (kept.length < maxArchivedStates && !entry.lastUsedAt.isBefore(cutoff)) {
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
            {'lastUsedAt': entry.lastUsedAt.toUtc().toIso8601String(), 'state': entry.state.toJson()},
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
              DateTime.parse(raw['lastUsedAt'] as String).toUtc(),
            ),
        ],
      );
    } catch (_) {
      return null;
    }
  }
}
