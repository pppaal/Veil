// Double Ratchet state and steps (docs/crypto-envelope-spec.md §Double
// Ratchet), a port of the mobile reference (ratchet_state.dart,
// double_ratchet.dart).
//
// A state is mutable on purpose, but only ever mutated on a private copy():
// the session cipher commits the copy once the AEAD has verified and the copy
// is durable, so a failed or concurrent operation never rolls state back.
// The sending ratchet private key is a non-extractable CryptoKey; roots,
// chains and skipped message keys are bytes, sealed at rest by the session
// repository.

import { decodeBase64Url, encodeBase64Url } from '../core/base64url.js';
import { constantTimeEqual, zeroize } from './bytes.js';
import { deriveMessageKey, kdfRoot, nextChainKey } from './kdf.js';
import { KeyAgreementError, x25519 } from './keys.js';

// Most keys one received frame may make us derive and stash (PN stash and N
// stash together). Bounds the HKDF work and memory a hostile header can
// demand.
export const MAX_SKIP_PER_STEP = 200;
// Session-wide stash; beyond it the oldest skipped keys are evicted.
export const MAX_SKIPPED_KEYS = 1000;
// Older skipped keys are abandoned stragglers; dropping them stops a peer
// from pinning key slots forever.
const SKIPPED_KEY_TTL_MS = 7 * 24 * 60 * 60 * 1000;
const MAX_PREVIOUS_REMOTE_KEYS = 32;

const skippedKeyId = (ratchetPublic, counter) => `${encodeBase64Url(ratchetPublic)}|${counter}`;
const copyBytes = (bytes) => (bytes ? bytes.slice() : null);

export class RatchetState {
  constructor(fields) {
    this.remoteDeviceId = fields.remoteDeviceId;
    this.initiatedLocally = fields.initiatedLocally;
    this.createdAt = fields.createdAt;
    // Ed25519 identity keys the handshake bound, and its AD.
    this.localIdentityKey = fields.localIdentityKey;
    this.remoteIdentityKey = fields.remoteIdentityKey;
    this.associatedData = fields.associatedData;
    // EK_A of the handshake that created this state: PreKey frames carrying
    // it belong here rather than opening a new state.
    this.baseKey = fields.baseKey;
    // Encoded PreKey header the initiator repeats until the first reply.
    this.pendingPreKeyHeader = fields.pendingPreKeyHeader ?? null;
    this.rootKey = fields.rootKey;
    this.sendChainKey = fields.sendChainKey ?? null;
    this.receiveChainKey = fields.receiveChainKey ?? null;
    this.sendCounter = fields.sendCounter ?? 0;
    this.receiveCounter = fields.receiveCounter ?? 0;
    this.previousSendCounter = fields.previousSendCounter ?? 0;
    // { privateKey: CryptoKey, publicKey: bytes }
    this.sendRatchet = fields.sendRatchet;
    this.remoteRatchetPublic = fields.remoteRatchetPublic ?? null;
    // Set by a receive DH step: the next send must rotate our ratchet key.
    this.needsSendStep = fields.needsSendStep ?? false;
    // Insertion-ordered, so the oldest entry is evicted first.
    this.skipped = fields.skipped ?? new Map();
    // Ratchet keys the peer has moved past: a frame naming one with no
    // stashed key is a replay, not a reason to attempt a DH step.
    this.previousRemoteRatchetKeys = fields.previousRemoteRatchetKeys ?? [];
  }

  get awaitingFirstReply() {
    return this.pendingPreKeyHeader !== null;
  }

  // A handshake not yet acknowledged from our side: we initiated it and have
  // not heard back, or the peer did and we have not replied.
  get handshakePending() {
    return this.initiatedLocally ? this.awaitingFirstReply : this.sendChainKey === null;
  }

  get initiatorIdentityKey() {
    return this.initiatedLocally ? this.localIdentityKey : this.remoteIdentityKey;
  }

  copy() {
    const skipped = new Map();
    for (const [id, entry] of this.skipped) skipped.set(id, { key: entry.key.slice(), stashedAt: entry.stashedAt });
    return new RatchetState({
      ...this,
      localIdentityKey: this.localIdentityKey.slice(),
      remoteIdentityKey: this.remoteIdentityKey.slice(),
      associatedData: this.associatedData.slice(),
      baseKey: this.baseKey.slice(),
      pendingPreKeyHeader: copyBytes(this.pendingPreKeyHeader),
      rootKey: this.rootKey.slice(),
      sendChainKey: copyBytes(this.sendChainKey),
      receiveChainKey: copyBytes(this.receiveChainKey),
      sendRatchet: { privateKey: this.sendRatchet.privateKey, publicKey: this.sendRatchet.publicKey.slice() },
      remoteRatchetPublic: copyBytes(this.remoteRatchetPublic),
      skipped,
      previousRemoteRatchetKeys: [...this.previousRemoteRatchetKeys],
    });
  }

  // Wipes the secret bytes this object owns: the losing side of a commit.
  destroy() {
    zeroize(this.rootKey, this.sendChainKey, this.receiveChainKey);
    this.clearSkipped();
  }

  clearSkipped() {
    for (const entry of this.skipped.values()) zeroize(entry.key);
    this.skipped.clear();
  }

  pruneSkipped(nowMs) {
    for (const [id, entry] of this.skipped) {
      if (nowMs - entry.stashedAt > SKIPPED_KEY_TTL_MS) {
        zeroize(entry.key);
        this.skipped.delete(id);
      }
    }
  }

  evictSkippedBeyond(limit) {
    for (const [id, entry] of this.skipped) {
      if (this.skipped.size <= limit) return;
      zeroize(entry.key);
      this.skipped.delete(id);
    }
  }

  // JSON-safe form; CryptoKeys go to `keyRefs` and are named by index, so the
  // repository can seal the JSON and store the keys by structured clone.
  toSnapshot(keyRefs) {
    keyRefs.push(this.sendRatchet.privateKey);
    const b64 = (bytes) => (bytes ? encodeBase64Url(bytes) : null);
    return {
      remoteDeviceId: this.remoteDeviceId,
      initiatedLocally: this.initiatedLocally,
      createdAt: this.createdAt,
      localIdentityKey: b64(this.localIdentityKey),
      remoteIdentityKey: b64(this.remoteIdentityKey),
      associatedData: b64(this.associatedData),
      baseKey: b64(this.baseKey),
      pendingPreKeyHeader: b64(this.pendingPreKeyHeader),
      rootKey: b64(this.rootKey),
      sendChainKey: b64(this.sendChainKey),
      receiveChainKey: b64(this.receiveChainKey),
      sendCounter: this.sendCounter,
      receiveCounter: this.receiveCounter,
      previousSendCounter: this.previousSendCounter,
      sendRatchetKeyRef: keyRefs.length - 1,
      sendRatchetPublic: b64(this.sendRatchet.publicKey),
      remoteRatchetPublic: b64(this.remoteRatchetPublic),
      needsSendStep: this.needsSendStep,
      skipped: [...this.skipped].map(([id, entry]) => [id, b64(entry.key), entry.stashedAt]),
      previousRemoteRatchetKeys: [...this.previousRemoteRatchetKeys],
    };
  }

  static fromSnapshot(snapshot, keyRefs, nowMs) {
    const bytes = (text) => (typeof text === 'string' ? decodeBase64Url(text) : null);
    const state = new RatchetState({
      ...snapshot,
      localIdentityKey: bytes(snapshot.localIdentityKey),
      remoteIdentityKey: bytes(snapshot.remoteIdentityKey),
      associatedData: bytes(snapshot.associatedData),
      baseKey: bytes(snapshot.baseKey),
      pendingPreKeyHeader: bytes(snapshot.pendingPreKeyHeader),
      rootKey: bytes(snapshot.rootKey),
      sendChainKey: bytes(snapshot.sendChainKey),
      receiveChainKey: bytes(snapshot.receiveChainKey),
      sendRatchet: { privateKey: keyRefs[snapshot.sendRatchetKeyRef], publicKey: bytes(snapshot.sendRatchetPublic) },
      remoteRatchetPublic: bytes(snapshot.remoteRatchetPublic),
      skipped: new Map(snapshot.skipped.map(([id, key, stashedAt]) => [id, { key: bytes(key), stashedAt }])),
    });
    // A long-closed tab must not resurrect week-old stragglers.
    state.pruneSkipped(nowMs);
    return state;
  }
}

// The initiator's first DH ratchet step against the responder's signed
// prekey: (RK, CKs) = KDF_RK(SK, DH(DHs, SPK_B)).
export async function deriveInitialSendingChain(subtle, keys, sharedKey, remoteSignedPrekey) {
  const ratchet = await keys.x25519();
  const dh = await x25519(subtle, ratchet.privateKey, remoteSignedPrekey);
  const { rootKey, chainKey } = await kdfRoot(subtle, sharedKey, dh);
  zeroize(dh);
  return { ratchet, rootKey, chainKey };
}

export async function advanceSendingChain(subtle, keys, state) {
  if (state.needsSendStep) await sendDhStep(subtle, keys, state);
  const chain = state.sendChainKey;
  if (!chain) throw new Error('session has no sending chain yet');
  const counter = state.sendCounter;
  const messageKey = await deriveMessageKey(subtle, chain, counter);
  state.sendChainKey = await nextChainKey(subtle, chain);
  zeroize(chain);
  state.sendCounter = counter + 1;
  return {
    ratchetPublic: state.sendRatchet.publicKey.slice(),
    previousCounter: state.previousSendCounter,
    counter,
    messageKey,
  };
}

// Resolves the message key for header (ratchetPublic, PN, N), stepping the
// ratchet as needed. Resolves to { messageKey }, { replayed: true } or
// { rejected: reason }.
export async function resolveReceivingKey(subtle, state, { ratchetPublic, previousCounter, counter, nowMs }) {
  state.pruneSkipped(nowMs);
  // A stashed key decrypts a straggler without touching the ratchet; a DH
  // step first would corrupt the session.
  const stashedId = skippedKeyId(ratchetPublic, counter);
  const stashed = state.skipped.get(stashedId);
  if (stashed) {
    state.skipped.delete(stashedId);
    return { messageKey: stashed.key };
  }
  if (state.previousRemoteRatchetKeys.includes(encodeBase64Url(ratchetPublic))) return { replayed: true };

  let budget = MAX_SKIP_PER_STEP;
  const current = state.remoteRatchetPublic;
  if (!current || !constantTimeEqual(current, ratchetPublic)) {
    if (current && state.receiveChainKey) {
      // Keys the peer sent on the chain it is leaving: stash them under the
      // OLD ratchet key so late messages from that turn still decrypt.
      const stashCount = previousCounter - state.receiveCounter;
      if (stashCount > budget) return { rejected: 'skip_limit' };
      if (stashCount > 0) {
        await stashUntil(subtle, state, current, previousCounter, nowMs);
        budget -= stashCount;
      }
    }
    if (current) rememberPreviousRemoteKey(state, current);
    try {
      await receiveDhStep(subtle, state, ratchetPublic);
    } catch (error) {
      if (error instanceof KeyAgreementError) return { rejected: 'low_order_ratchet_key' };
      throw error;
    }
  } else if (counter < state.receiveCounter) {
    return { replayed: true };
  }

  if (!state.receiveChainKey) return { rejected: 'no_receiving_chain' };
  if (counter - state.receiveCounter > budget) return { rejected: 'skip_limit' };
  await stashUntil(subtle, state, ratchetPublic, counter, nowMs);
  const chain = state.receiveChainKey;
  const messageKey = await deriveMessageKey(subtle, chain, counter);
  state.receiveChainKey = await nextChainKey(subtle, chain);
  zeroize(chain);
  state.receiveCounter = counter + 1;
  state.evictSkippedBeyond(MAX_SKIPPED_KEYS);
  return { messageKey };
}

async function stashUntil(subtle, state, ratchetPublic, until, nowMs) {
  while (state.receiveCounter < until) {
    const chain = state.receiveChainKey;
    const key = await deriveMessageKey(subtle, chain, state.receiveCounter);
    state.skipped.set(skippedKeyId(ratchetPublic, state.receiveCounter), { key, stashedAt: nowMs });
    state.receiveChainKey = await nextChainKey(subtle, chain);
    zeroize(chain);
    state.receiveCounter += 1;
  }
}

function rememberPreviousRemoteKey(state, ratchetPublic) {
  state.previousRemoteRatchetKeys.push(encodeBase64Url(ratchetPublic));
  if (state.previousRemoteRatchetKeys.length > MAX_PREVIOUS_REMOTE_KEYS) state.previousRemoteRatchetKeys.shift();
}

async function receiveDhStep(subtle, state, ratchetPublic) {
  const dh = await x25519(subtle, state.sendRatchet.privateKey, ratchetPublic);
  const { rootKey, chainKey } = await kdfRoot(subtle, state.rootKey, dh);
  zeroize(dh, state.rootKey, state.receiveChainKey);
  state.rootKey = rootKey;
  state.receiveChainKey = chainKey;
  state.receiveCounter = 0;
  state.remoteRatchetPublic = ratchetPublic.slice();
  state.needsSendStep = true;
}

async function sendDhStep(subtle, keys, state) {
  const remote = state.remoteRatchetPublic;
  if (!remote) throw new Error('cannot rotate the sending ratchet before receiving a peer ratchet key');
  const ratchet = await keys.x25519();
  const dh = await x25519(subtle, ratchet.privateKey, remote);
  const { rootKey, chainKey } = await kdfRoot(subtle, state.rootKey, dh);
  zeroize(dh, state.rootKey, state.sendChainKey);
  state.previousSendCounter = state.sendCounter;
  state.sendCounter = 0;
  state.rootKey = rootKey;
  state.sendChainKey = chainKey;
  state.sendRatchet = ratchet;
  state.needsSendStep = false;
}
