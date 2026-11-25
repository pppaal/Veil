// This device's prekeys: the responder's side of X3DH and the lifecycle that
// keeps the directory stocked (docs/crypto-envelope-spec.md §Identity keys
// and the bundle, §X3DH).
//
// The identity record (src/platform/session-store.js) holds
//   ik             { privateKey, publicKey }              Ed25519 IK
//   ikx            { privateKey, publicKey, signature }   X25519 IKx + ikxSig
//   signedPrekeys  [{ id, privateKey, publicKey, createdAt, publishedAt,
//                     supersededAt, refusedAt? }]
//   nextOneTimePrekeyId
//   oneTimePrekeyUpload  { firstId, count } of the batch whose upload is not
//                        confirmed yet, or null
// and one-time prekey private keys live in their own store, one row per key,
// so using one deletes exactly that row. Every private key is a
// non-extractable CryptoKey.
//
// Signed prekeys are stamped (createdAt, the bundle's spkTs) and aged on the
// server's clock: this device's clock corrected by the HTTP Date header
// (src/platform/api-client.js serverNow). The directory accepts a stamp at
// most an hour old and 10 minutes ahead (contract C-SPK), so a device whose
// clock is off can still rotate.

import { decodeBase64Url, encodeBase64Url } from '../core/base64url.js';
import { BundleError, signBundle } from './bundle.js';
import { NO_ONE_TIME_PREKEY_ID } from './x3dh.js';

const DAY_MS = 24 * 60 * 60 * 1000;
export const SIGNED_PREKEY_ROTATION_MS = 7 * DAY_MS;
// A superseded SPK still answers handshakes started from a bundle fetched
// before the rotation, for this long after its successor was published.
export const SIGNED_PREKEY_GRACE_MS = 14 * DAY_MS;
// An unpublished signed prekey is published again as it is while younger
// than this; an older one is replaced by a successor (contract C-SPK).
export const SIGNED_PREKEY_RESEND_MS = 30 * 60 * 1000;
export const ONE_TIME_PREKEY_BATCH = 100;
const ONE_TIME_PREKEY_LOW_WATER = 20;
export const PREKEY_LOCK = 'veil-prekeys';

// Whether a signed prekey still answers handshakes. A superseded one does
// for the grace period after its successor was published, for bundles
// fetched before that. One whose publication was never confirmed may still
// have reached the directory (only the response was lost), so it is kept
// for as long from when it was drawn.
function isRetained(spk, nowMs) {
  if (spk.supersededAt !== null) return nowMs - spk.supersededAt <= SIGNED_PREKEY_GRACE_MS;
  return spk.publishedAt !== null || nowMs - spk.createdAt <= SIGNED_PREKEY_GRACE_MS;
}

// The signed prekey the directory serves, of an identity's signedPrekeys.
export const currentSignedPrekey = (signedPrekeys) =>
  signedPrekeys.find((spk) => spk.publishedAt !== null && spk.supersededAt === null);

export class PrekeyUnavailableError extends Error {
  // reason: 'spk_unavailable' | 'opk_unavailable'
  constructor(reason) {
    super(reason);
    this.name = 'PrekeyUnavailableError';
    this.reason = reason;
  }
}

// loadIdentity() -> the identity record as stored now: another tab may have
// rotated the signed prekey since this one loaded it. opkKv rows are
// { keyId, privateKey, publicKey }.
export function createLocalKeyring({ loadIdentity, opkKv, clock }) {
  // One-time prekeys held by a handshake in flight, and ones already used
  // whose stored row may not be gone yet: neither may open a second session.
  const claimed = new Set();
  const spent = new Set();

  function signedPrekey(identity, id) {
    const entry = identity.signedPrekeys?.find((spk) => spk.id === id);
    if (!entry || !isRetained(entry, clock())) throw new PrekeyUnavailableError('spk_unavailable');
    return { privateKey: entry.privateKey, publicKey: entry.publicKey };
  }

  const publicIdentity = ({ ik, ikx }) => ({
    ed25519Public: ik.publicKey,
    x25519Private: ikx.privateKey,
    x25519Public: ikx.publicKey,
    ikxSignature: ikx.signature,
  });

  return {
    // What an initiator needs of us: IK, IKx and IKx's certificate.
    localIdentity: async () => publicIdentity(await loadIdentity()),

    // Fails without changing anything when a named prekey is gone.
    async claimHandshakePrekeys(header) {
      const identity = await loadIdentity();
      const signed = signedPrekey(identity, header.signedPrekeyId);
      let oneTimePrekeyPrivate = null;
      if (header.oneTimePrekeyId !== NO_ONE_TIME_PREKEY_ID) {
        const keyId = header.oneTimePrekeyId;
        if (claimed.has(keyId) || spent.has(keyId)) throw new PrekeyUnavailableError('opk_unavailable');
        const row = await opkKv.get(keyId);
        if (!row) throw new PrekeyUnavailableError('opk_unavailable');
        claimed.add(keyId);
        oneTimePrekeyPrivate = row.privateKey;
      }
      return { identity: publicIdentity(identity), signedPrekey: signed, oneTimePrekeyPrivate };
    },

    release(header) {
      claimed.delete(header.oneTimePrekeyId);
    },

    // Called once the session the OPK opened is durable. Marked spent first,
    // so a failed delete still cannot open a second session in this tab.
    async consumeOneTimePrekey(keyId) {
      spent.add(keyId);
      await opkKv.delete(keyId);
    },
  };
}

// Keeps the directory able to start sessions with us: rotates the signed
// prekey weekly, drops superseded ones after their grace period, and tops the
// one-time pool back up to a full batch when it runs low. A failed rotation
// never holds up the one-time prekeys: they are topped up all the same, and
// the rotation's error is thrown after. Callers serialize runs across tabs
// with PREKEY_LOCK.
//   identity: { current() -> record, update(fields) -> saves the record }
//   clock() -> the server-corrected time (ms)
export async function maintainPrekeys({ subtle, keys, authedApi, identity, opkKv, clock }) {
  let rotationError = null;
  try {
    await rotateSignedPrekeyIfDue({ subtle, keys, authedApi, identity, nowMs: clock() });
  } catch (error) {
    rotationError = error;
  }
  await replenishOneTimePrekeys({ keys, authedApi, identity, opkKv });
  if (rotationError) throw rotationError;
}

// The directory turned the bundle down for what it is (its timestamp out of
// the window, a repeated id after an answer that was lost, a bad bundle):
// sending it again would only be refused again. Network failures, 5xx and
// 429 are not refusals.
const isRefusal = (error) => error?.status >= 400 && error.status < 500 && error.status !== 429;

async function rotateSignedPrekeyIfDue({ subtle, keys, authedApi, identity, nowMs }) {
  const record = identity.current();
  const live = record.signedPrekeys.filter((spk) => isRetained(spk, nowMs));
  const current = currentSignedPrekey(live);
  if (current && nowMs - current.createdAt < SIGNED_PREKEY_ROTATION_MS) {
    if (live.length !== record.signedPrekeys.length) await identity.update({ signedPrekeys: live });
    return;
  }
  // The successor is stored before it is published, so a frame sent to it
  // the moment the directory serves it already finds its private key. One
  // whose publication failed is published again as it is while it is young
  // enough for the directory's window and was not refused; otherwise a
  // fresh successor is drawn under a new id. Failed ones are kept: one may
  // have arrived after all with only the answer lost, and each is
  // superseded like the current one once a successor is published.
  let successor = live.find((spk) => spk.publishedAt === null && spk.supersededAt === null && !spk.refusedAt
    && nowMs - spk.createdAt < SIGNED_PREKEY_RESEND_MS);
  if (!successor) {
    const pair = await keys.x25519();
    successor = {
      id: Math.max(0, ...record.signedPrekeys.map((spk) => spk.id)) + 1,
      privateKey: pair.privateKey,
      publicKey: pair.publicKey,
      createdAt: nowMs,
      publishedAt: null,
      supersededAt: null,
    };
    live.unshift(successor);
  }
  await identity.update({ signedPrekeys: live });
  // Ed25519 is deterministic: the same prekey always makes the same bundle.
  const signedPrekeyBundle = await signBundle(subtle, record.ik.privateKey, {
    ikx: record.ikx.publicKey,
    ikxSig: record.ikx.signature,
    spk: successor,
  });
  const others = live.filter((spk) => spk !== successor);
  try {
    await authedApi('/keys/signed-prekey', { method: 'PUT', body: { signedPrekeyBundle } });
  } catch (error) {
    if (isRefusal(error)) {
      await identity.update({ signedPrekeys: [{ ...successor, refusedAt: nowMs }, ...others] });
    }
    throw error;
  }
  await identity.update({
    signedPrekeys: [
      { ...successor, publishedAt: nowMs },
      ...others.map((spk) => (spk.supersededAt === null ? { ...spk, supersededAt: nowMs } : spk)),
    ],
  });
}

// A batch whose upload was not confirmed goes up again as it is on the next
// run (the directory skips ids it already holds), never replaced by fresh
// keys, unless the directory refuses it: then it never stored it, and its
// keys are dropped so that one bad batch cannot stop every later top-up.
// Then the pool is topped up if it runs low.
async function replenishOneTimePrekeys({ keys, authedApi, identity, opkKv }) {
  const unconfirmed = identity.current().oneTimePrekeyUpload ?? null;
  if (unconfirmed) {
    try {
      await uploadOneTimePrekeys({ authedApi, identity, opkKv, batch: unconfirmed });
    } catch (error) {
      if (!isRefusal(error)) throw error;
      for (const keyId of keyIdsOf(unconfirmed)) await opkKv.delete(keyId);
      await identity.update({ oneTimePrekeyUpload: null });
    }
  }
  const { available } = await authedApi('/prekeys/count');
  if (available >= ONE_TIME_PREKEY_LOW_WATER) return;
  await uploadOneTimePrekeys({ authedApi, identity, opkKv, batch: await drawOneTimePrekeys({ keys, identity, opkKv }) });
}

const keyIdsOf = (batch) => Array.from({ length: batch.count }, (_, i) => batch.firstId + i);

// Ids are allocated monotonically and saved, with the batch marked
// unconfirmed, before any key is drawn, so an id is never reused even when
// an upload fails half-way.
async function drawOneTimePrekeys({ keys, identity, opkKv }) {
  const batch = { firstId: identity.current().nextOneTimePrekeyId, count: ONE_TIME_PREKEY_BATCH };
  await identity.update({ nextOneTimePrekeyId: batch.firstId + batch.count, oneTimePrekeyUpload: batch });
  for (const keyId of keyIdsOf(batch)) {
    const pair = await keys.x25519();
    await opkKv.put({ keyId, privateKey: pair.privateKey, publicKey: pair.publicKey });
  }
  return batch;
}

// Uploads the batch's keys this device still holds: one already used was
// handed out by the directory, which therefore had it.
async function uploadOneTimePrekeys({ authedApi, identity, opkKv, batch }) {
  const prekeys = [];
  for (const keyId of keyIdsOf(batch)) {
    const row = await opkKv.get(keyId);
    if (row) prekeys.push({ keyId, publicKey: encodeBase64Url(row.publicKey) });
  }
  if (prekeys.length > 0) await authedApi('/prekeys', { method: 'POST', body: { prekeys } });
  await identity.update({ oneTimePrekeyUpload: null });
}

// A one-time prekey the directory handed out, validated before use. A
// malformed one rejects the peer's bundle as a whole, as a bad signed
// prekey does.
export function claimedOneTimePrekey(raw) {
  if (!raw) return null;
  const validId = Number.isInteger(raw.keyId) && raw.keyId >= 0 && raw.keyId < NO_ONE_TIME_PREKEY_ID;
  let publicKey = null;
  try {
    publicKey = decodeBase64Url(raw.publicKey);
  } catch {
    throw new BundleError('malformed');
  }
  if (!validId || publicKey.length !== 32) throw new BundleError('malformed');
  return { keyId: raw.keyId, publicKey };
}
