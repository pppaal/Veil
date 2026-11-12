// All ratchet states of one conversation: the state we send on plus archived
// states that may still receive in-flight messages (re-bootstrap, glare, a
// peer that re-initiated). A port of the mobile reference session_record.dart;
// the rules are docs/crypto-envelope-spec.md §Session records and glare, and
// both clients must apply them identically to converge.
//
// Records are immutable: every transition returns the next record. States a
// transition leaves out are wiped by the session cipher with everything else
// it loaded, once the operation ends.

import { compareBytes } from './bytes.js';
import { RatchetState } from './ratchet.js';

const MAX_ARCHIVED_STATES = 5;
// Counted from an archived state's last use, so a state the peer still sends
// on is never dropped while it is in use.
const ARCHIVED_STATE_RETENTION_MS = 30 * 24 * 60 * 60 * 1000;

export class SessionRecord {
  // archived: [{ state, lastUsedAt }], most recently used first.
  constructor({ current, archived = [] }) {
    this.current = current;
    this.archived = Object.freeze([...archived]);
  }

  get states() {
    return [this.current, ...this.archived.map((entry) => entry.state)];
  }

  // Swaps `live` for its updated copy, wherever it sits in the record.
  replacing(live, replacement, nowMs) {
    if (live === this.current) return this.#pruned(replacement, this.archived, nowMs);
    return this.#pruned(this.current, [{ state: replacement, lastUsedAt: nowMs }, ...this.#archivedExcept(live)], nowMs);
  }

  // Commits `replacement`, the copy of `live` that just authenticated a
  // received message. A peer sends on the state it last chose, so an
  // archived state that receives becomes the sending state as well
  // (libsignal's promoteState): each side ends up sending on the state its
  // peer last used, whatever order frames arrive in.
  receiving(live, replacement, nowMs) {
    if (live === this.current || !(this.#mayDisplaceCurrent(replacement) || this.#peerAbandonedOurs(live))) {
      return this.replacing(live, replacement, nowMs);
    }
    return this.#pruned(replacement, [{ state: this.current, lastUsedAt: nowMs }, ...this.#archivedExcept(live)], nowMs);
  }

  // `state` becomes the sending state; the old one is archived, never
  // destroyed, so messages already in flight on it still decrypt.
  promoting(state, nowMs) {
    return this.#pruned(state, [{ state: this.current, lastUsedAt: nowMs }, ...this.archived], nowMs);
  }

  archiving(state, nowMs) {
    return this.#pruned(this.current, [{ state, lastUsedAt: nowMs }, ...this.archived], nowMs);
  }

  // Installs a state the peer just opened with a PreKey frame. It is the
  // peer's newest handshake, so it becomes the sending state unless it
  // competes with our own unanswered initiation and loses the glare
  // tie-break.
  static installingInbound(record, incoming, nowMs) {
    if (!record) return new SessionRecord({ current: incoming });
    const { current } = record;
    return current.initiatedLocally && handshakeHolds(current, incoming)
      ? record.archiving(incoming, nowMs)
      : record.promoting(incoming, nowMs);
  }

  // Never across identities: a state bound to another identity must not win
  // the sending role back just because it still receives.
  #mayDisplaceCurrent(candidate) {
    return compareBytes(this.current.remoteIdentityKey, candidate.remoteIdentityKey) === 0
      && !handshakeHolds(this.current, candidate);
  }

  // Our initiation is still unanswered while the peer sends a further frame
  // on a handshake of its own that we never answered. A peer that holds our
  // handshake would not keep sending on its own, so it did not take ours,
  // typically because it could not open it (the one-time or signed prekey it
  // names is gone): holding on to ours would leave every message we send
  // unreadable for good. The first competing frame (`live` has received
  // nothing yet) still loses glare as specified, so true glare settles as
  // before, and a state we already sent on never qualifies. The mobile
  // reference applies the same rule (session_record.dart _peerAbandonedOurs).
  #peerAbandonedOurs(live) {
    const { current } = this;
    return current.initiatedLocally
      && current.awaitingFirstReply
      && !live.initiatedLocally
      && live.handshakePending
      && live.receiveCounter > 0
      && compareBytes(current.remoteIdentityKey, live.remoteIdentityKey) === 0;
  }

  #archivedExcept(state) {
    return this.archived.filter((entry) => entry.state !== state);
  }

  #pruned(nextCurrent, nextArchived, nowMs) {
    const kept = nextArchived
      .filter((entry) => nowMs - entry.lastUsedAt <= ARCHIVED_STATE_RETENTION_MS)
      .slice(0, MAX_ARCHIVED_STATES);
    return new SessionRecord({ current: nextCurrent, archived: kept });
  }

  toSnapshot(keyRefs) {
    return {
      current: this.current.toSnapshot(keyRefs),
      archived: this.archived.map((entry) => ({ lastUsedAt: entry.lastUsedAt, state: entry.state.toSnapshot(keyRefs) })),
    };
  }

  static fromSnapshot(snapshot, keyRefs, nowMs) {
    return new SessionRecord({
      current: RatchetState.fromSnapshot(snapshot.current, keyRefs, nowMs),
      archived: snapshot.archived.map((entry) => ({
        lastUsedAt: entry.lastUsedAt,
        state: RatchetState.fromSnapshot(entry.state, keyRefs, nowMs),
      })),
    });
  }
}

// Glare tie-break. While `current`'s handshake is pending (our initiation
// the peer has not answered, or the peer's that we have not answered), the
// peer may not have seen it yet, so its traffic on `competitor` does not show
// which state it settled on. `current` therefore holds unless `competitor`
// was initiated by the party with the bytewise lower identity key: the
// comparison the peer applies to the same two handshakes, so both settle on
// one.
function handshakeHolds(current, competitor) {
  if (!current.handshakePending) return false;
  return compareBytes(competitor.initiatorIdentityKey, current.initiatorIdentityKey) >= 0;
}
