// Trust on first use for peers' Ed25519 identity keys, pinned per
// (userId, deviceId) in IndexedDB ('identity-pins-v2':
// { id: userId/deviceId, userId, deviceId, identityKey (b64u), firstSeenAt,
//   verifiedAt }, indexed by userId). The same store keeps the keys the user
// declined: { id: userId/deviceId!identityKey, userId, deviceId,
// identityKey, refusedAt }.
//
// The first key seen for a user is pinned. After that, a different key for a
// pinned device, or a device the user has never used with us, is an identity
// change: it never replaces a pin by itself. The directory path (before a
// session is started), the inbound path (an authenticated PreKey frame) and
// every frame a session seals or opens go through admit()
// (src/crypto/session-cipher.js), so a change freezes the conversation
// whichever way the server tries it, until the user decides.
//
// Accepting a new device adds its pin and keeps the user's earlier ones:
// people use several devices, and one they move away from may come back.
// While a contact is unverified, the relay can therefore route sessions to
// an earlier accepted device without a fresh warning. Verifying a safety
// number ends that: from then on only devices whose own key the user
// verified pass, so a key accepted blindly before (a relay's, on first
// contact) cannot take the conversation back from the one they compared.
// For a verified contact a plain accept is refused; each device is verified.
//
// The user may also decline a change ("not their key"): that device and key
// are refused from then on without asking again, and the conversation goes
// on with the identity its session already sends to. Without this, anyone
// able to complete a handshake against our published prekeys (the relay, with
// an identity of its own) could freeze a conversation for good: a frame
// refused while a change is pending is opened again on every history
// refresh and reload, and raises the change again each time. Declining adds
// no trust, so it is open to verified contacts too; only accepting or
// verifying that key undoes it.

import { decodeBase64Url, encodeBase64Url } from '../core/base64url.js';
import { createLocks } from './locks.js';

export const PinVerdict = Object.freeze({
  FIRST_USE: 'first-use',
  MATCH: 'match',
  NEW_DEVICE: 'new-device',
  CHANGED: 'changed',
  // the pinned key of a device the user never verified, of a contact whose
  // safety number they did verify on another device
  UNVERIFIED_DEVICE: 'unverified-device',
  // a device and key the user declined
  REFUSED: 'refused',
});

export class ReverificationRequiredError extends Error {
  constructor(userId) {
    super('this contact was verified: compare the new safety number to accept the change');
    this.name = 'ReverificationRequiredError';
    this.userId = userId;
  }
}

// kv: src/platform/kv.js over 'identity-pins-v2' (byIndex: by userId).
// Every operation reads a user's pins and then writes one, so operations on
// the same user run one at a time under locks (src/crypto/locks.js; the app
// passes its cross-tab locks): two first contacts in different conversations
// cannot both find no pins and both pin.
export function createPinStore(kv, { now = () => Date.now(), locks = createLocks(null) } = {}) {
  const isRefusal = (row) => row.refusedAt !== undefined;
  const forUser = async (userId) => (await kv.byIndex(userId)).filter((row) => !isRefusal(row));
  const serialized = (userId, task) => locks.run(`veil-pins:${userId}`, task);
  const refusalId = (userId, deviceId, identityKey) => `${userId}/${deviceId}!${encodeBase64Url(identityKey)}`;
  const pinOf = (userId, deviceId, identityKey, verifiedAt, firstSeenAt = now()) => ({
    id: `${userId}/${deviceId}`,
    userId,
    deviceId,
    identityKey: encodeBase64Url(identityKey),
    firstSeenAt,
    verifiedAt,
  });

  return {
    // { verdict, verified, pin }. Pins (and reports FIRST_USE) only for a
    // user with no pins at all.
    check: (userId, deviceId, identityKey) => serialized(userId, async () => {
      if (await kv.get(refusalId(userId, deviceId, identityKey))) {
        return { verdict: PinVerdict.REFUSED, verified: false, pin: null };
      }
      const pins = await forUser(userId);
      const verified = pins.some((pin) => pin.verifiedAt !== null);
      const pin = pins.find((candidate) => candidate.deviceId === deviceId) ?? null;
      if (pin) {
        if (pin.identityKey !== encodeBase64Url(identityKey)) return { verdict: PinVerdict.CHANGED, verified, pin };
        const verdict = verified && pin.verifiedAt === null ? PinVerdict.UNVERIFIED_DEVICE : PinVerdict.MATCH;
        return { verdict, verified, pin };
      }
      if (pins.length > 0) return { verdict: PinVerdict.NEW_DEVICE, verified, pin: null };
      const fresh = pinOf(userId, deviceId, identityKey, null);
      await kv.put(fresh);
      return { verdict: PinVerdict.FIRST_USE, verified: false, pin: fresh };
    }),

    accept: (userId, deviceId, identityKey) => serialized(userId, async () => {
      const pins = await forUser(userId);
      if (pins.some((pin) => pin.verifiedAt !== null)) throw new ReverificationRequiredError(userId);
      await kv.put(pinOf(userId, deviceId, identityKey, null));
      await kv.delete(refusalId(userId, deviceId, identityKey));
    }),

    // The user compared safety numbers for this key out of band.
    markVerified: (userId, deviceId, identityKey) => serialized(userId, async () => {
      const existing = (await forUser(userId)).find((pin) => pin.deviceId === deviceId);
      const sameKey = existing?.identityKey === encodeBase64Url(identityKey);
      await kv.put(pinOf(userId, deviceId, identityKey, now(), sameKey ? existing.firstSeenAt : now()));
      await kv.delete(refusalId(userId, deviceId, identityKey));
    }),

    // The user declined this key for this device; it pins nothing.
    refuse: (userId, deviceId, identityKey) => serialized(userId, () => kv.put({
      id: refusalId(userId, deviceId, identityKey),
      userId,
      deviceId,
      identityKey: encodeBase64Url(identityKey),
      refusedAt: now(),
    })),

    pinsFor: forUser,
  };
}

// The identity changes awaiting the user's decision, one per peer. Pending
// changes live in memory: after a reload the next directory lookup or
// inbound handshake reports them again, unless the user declined them.
export function createIdentityTrust({ pins, onChange = () => {} }) {
  const pending = new Map(); // userId -> { deviceId, identityKey, verdict, verified }
  const presents = (change, deviceId, identityKey) =>
    change?.deviceId === deviceId && encodeBase64Url(change.identityKey) === encodeBase64Url(identityKey);

  return {
    // True when this key may be used for the user; otherwise records the
    // change for review.
    async admit(userId, deviceId, identityKey) {
      const { verdict, verified } = await pins.check(userId, deviceId, identityKey);
      if (verdict === PinVerdict.FIRST_USE || verdict === PinVerdict.MATCH) return true;
      if (verdict === PinVerdict.REFUSED) return false;
      pending.set(userId, { deviceId, identityKey: identityKey.slice(), verdict, verified });
      onChange(userId);
      return false;
    },

    pendingChange: (userId) => pending.get(userId) ?? null,

    // Accepts `reviewed`, the pending change the user was shown, for an
    // unverified contact; a verified contact throws
    // ReverificationRequiredError. False, accepting nothing, when that
    // change is no longer the pending one: a later refusal replaced it, or
    // it was resolved meanwhile.
    async accept(userId, reviewed) {
      const change = pending.get(userId);
      if (!reviewed || !presents(change, reviewed.deviceId, reviewed.identityKey)) return false;
      await pins.accept(userId, change.deviceId, change.identityKey);
      pending.delete(userId);
      onChange(userId);
      return true;
    },

    // Declines `reviewed`, the pending change the user was shown: its device
    // and key are refused from now on, and nothing more waits for review.
    // False, declining nothing, when that change is no longer the pending
    // one, as for accept.
    async reject(userId, reviewed) {
      const change = pending.get(userId);
      if (!reviewed || !presents(change, reviewed.deviceId, reviewed.identityKey)) return false;
      await pins.refuse(userId, change.deviceId, change.identityKey);
      pending.delete(userId);
      onChange(userId);
      return true;
    },

    async markVerified(userId, deviceId, identityKey) {
      await pins.markVerified(userId, deviceId, identityKey);
      if (presents(pending.get(userId), deviceId, identityKey)) pending.delete(userId);
      onChange(userId);
    },

    // The key a safety number with this user is about: a key waiting for
    // review first, then the identity the conversation's session runs on
    // (session: { remoteDeviceId, remoteIdentityKey } or null), and only
    // while there is no session, the most recently pinned key. Never the
    // newest pin over the session's identity: what the user compares, and
    // verifies, must be the key their messages go to.
    // -> { deviceId, identityKey, pendingVerdict (null unless pending), verified } or null
    async safetyKey(userId, session) {
      const change = pending.get(userId);
      if (change) {
        const { deviceId, identityKey, verdict } = change;
        return { deviceId, identityKey: identityKey.slice(), pendingVerdict: verdict, verified: false };
      }
      const userPins = await pins.pinsFor(userId);
      if (session) {
        const pin = userPins.find((candidate) => candidate.deviceId === session.remoteDeviceId);
        return {
          deviceId: session.remoteDeviceId,
          identityKey: session.remoteIdentityKey,
          pendingVerdict: null,
          verified: pin?.identityKey === encodeBase64Url(session.remoteIdentityKey) && pin.verifiedAt !== null,
        };
      }
      const [latest] = userPins.sort((a, b) => b.firstSeenAt - a.firstSeenAt);
      if (!latest) return null;
      return {
        deviceId: latest.deviceId,
        identityKey: decodeBase64Url(latest.identityKey),
        pendingVerdict: null,
        verified: latest.verifiedAt !== null,
      };
    },

    reset() {
      pending.clear();
    },
  };
}
