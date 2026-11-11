// Trust on first use for peers' Ed25519 identity keys, pinned per
// (userId, deviceId) in IndexedDB ('identity-pins-v2':
// { id: userId/deviceId, userId, deviceId, identityKey (b64u), firstSeenAt,
//   verifiedAt }, indexed by userId).
//
// The first key seen for a user is pinned. After that, a different key for a
// pinned device, or a device the user has never used with us, is an identity
// change: it never replaces a pin by itself. Both the directory path (before
// a session is started) and the inbound path (an authenticated PreKey frame)
// go through admit(), so a change freezes the conversation whichever way the
// server tries it, until the user decides. A contact whose safety number was
// verified must verify the new one; a plain accept is refused.

import { encodeBase64Url } from '../core/base64url.js';

export const PinVerdict = Object.freeze({
  FIRST_USE: 'first-use',
  MATCH: 'match',
  NEW_DEVICE: 'new-device',
  CHANGED: 'changed',
});

export class ReverificationRequiredError extends Error {
  constructor(userId) {
    super('this contact was verified: compare the new safety number to accept the change');
    this.name = 'ReverificationRequiredError';
    this.userId = userId;
  }
}

// kv: src/platform/kv.js over 'identity-pins-v2' (byIndex: by userId).
export function createPinStore(kv, { now = () => Date.now() } = {}) {
  const forUser = (userId) => kv.byIndex(userId);
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
    async check(userId, deviceId, identityKey) {
      const pins = await forUser(userId);
      const verified = pins.some((pin) => pin.verifiedAt !== null);
      const pin = pins.find((candidate) => candidate.deviceId === deviceId) ?? null;
      if (pin) {
        const verdict = pin.identityKey === encodeBase64Url(identityKey) ? PinVerdict.MATCH : PinVerdict.CHANGED;
        return { verdict, verified, pin };
      }
      if (pins.length > 0) return { verdict: PinVerdict.NEW_DEVICE, verified, pin: null };
      const fresh = pinOf(userId, deviceId, identityKey, null);
      await kv.put(fresh);
      return { verdict: PinVerdict.FIRST_USE, verified: false, pin: fresh };
    },

    async accept(userId, deviceId, identityKey) {
      const pins = await forUser(userId);
      if (pins.some((pin) => pin.verifiedAt !== null)) throw new ReverificationRequiredError(userId);
      await kv.put(pinOf(userId, deviceId, identityKey, null));
    },

    // The user compared safety numbers for this key out of band.
    async markVerified(userId, deviceId, identityKey) {
      const existing = (await forUser(userId)).find((pin) => pin.deviceId === deviceId);
      const sameKey = existing?.identityKey === encodeBase64Url(identityKey);
      await kv.put(pinOf(userId, deviceId, identityKey, now(), sameKey ? existing.firstSeenAt : now()));
    },

    pinsFor: forUser,
  };
}

// The identity changes awaiting the user's decision, one per peer. Pending
// changes live in memory: after a reload the next directory lookup or
// inbound handshake reports them again.
export function createIdentityTrust({ pins, onChange = () => {} }) {
  const pending = new Map(); // userId -> { deviceId, identityKey, verdict, verified }

  return {
    // True when this key may be used for the user; otherwise records the
    // change for review.
    async admit(userId, deviceId, identityKey) {
      const { verdict, verified } = await pins.check(userId, deviceId, identityKey);
      if (verdict === PinVerdict.FIRST_USE || verdict === PinVerdict.MATCH) return true;
      pending.set(userId, { deviceId, identityKey: identityKey.slice(), verdict, verified });
      onChange(userId);
      return false;
    },

    pendingChange: (userId) => pending.get(userId) ?? null,

    // Accepts the pending key of an unverified contact; a verified contact
    // throws ReverificationRequiredError.
    async accept(userId) {
      const change = pending.get(userId);
      if (!change) return false;
      await pins.accept(userId, change.deviceId, change.identityKey);
      pending.delete(userId);
      onChange(userId);
      return true;
    },

    async markVerified(userId, deviceId, identityKey) {
      await pins.markVerified(userId, deviceId, identityKey);
      const change = pending.get(userId);
      if (change?.deviceId === deviceId && encodeBase64Url(change.identityKey) === encodeBase64Url(identityKey)) {
        pending.delete(userId);
      }
      onChange(userId);
    },

    reset() {
      pending.clear();
    },
  };
}
