// Trust on first use for peers' Ed25519 identity keys, pinned per
// (userId, deviceId) in IndexedDB ('identity-pins-v2':
// { id: userId/deviceId, userId, deviceId, identityKey (b64u), firstSeenAt,
//   verifiedAt }, indexed by userId). The same store keeps the keys the user
// declined: { id: refused/userId/deviceId/identityKey, userId, deviceId,
// identityKey, refusedAt }. Changes awaiting the user's decision are kept in
// 'identity-pending' ({ userId, deviceId, identityKey, verdict, verified }).
//
// The first key seen for a user is pinned. After that, a different key for a
// pinned device, or a device the user has never used with us, is an identity
// change: it never replaces a pin by itself. The directory path (before a
// session is started), the inbound path (an authenticated PreKey frame) and
// every frame a session seals or opens go through admit()
// (src/crypto/session-cipher.js), so nothing is installed, opened or sealed
// for a changed identity, whichever way the server tries it, until the user
// decides. A conversation whose session still sends to an admitted identity
// goes on sending meanwhile (src/features/secure-messaging.js prepare).
//
// A device id pinned under one user is refused under every other: the server
// assigns device ids, so a legitimate one never belongs to two users, and a
// relay that relabels a conversation's other member must not get a
// contact's device pinned, unannounced, as someone else's. There is nothing
// to approve in that case.
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
// an identity of its own) could keep a change in front of the user for good:
// a frame refused while a change is pending is opened again on every history
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
  // a device pinned under another user
  DEVICE_OF_OTHER_USER: 'device-of-other-user',
});

// Verdicts that refuse a key with nothing for the user to review.
const REFUSED_OUTRIGHT = new Set([PinVerdict.REFUSED, PinVerdict.DEVICE_OF_OTHER_USER]);

export class ReverificationRequiredError extends Error {
  constructor(userId) {
    super('this contact was verified: compare the new safety number to accept the change');
    this.name = 'ReverificationRequiredError';
    this.userId = userId;
  }
}

export class DeviceOfOtherUserError extends Error {
  constructor(deviceId) {
    super('this device is pinned under another contact');
    this.name = 'DeviceOfOtherUserError';
    this.deviceId = deviceId;
  }
}

// kv: src/platform/kv.js over 'identity-pins-v2' (byIndex: by userId).
// Every operation reads pins and then writes one, so operations run one at a
// time under one lock for the whole table (src/crypto/locks.js; the app
// passes its cross-tab locks): two first contacts in different conversations
// cannot both find no pins and both pin, and two users cannot both claim the
// same device.
export function createPinStore(kv, { now = () => Date.now(), locks = createLocks(null) } = {}) {
  const isRefusal = (row) => row.refusedAt !== undefined;
  const pinsOnly = (rows) => rows.filter((row) => !isRefusal(row));
  const forUser = async (userId) => pinsOnly(await kv.byIndex(userId));
  const serialized = (task) => locks.run('veil-pins', task);
  const refusalId = (userId, deviceId, identityKey) => `refused/${userId}/${deviceId}/${encodeBase64Url(identityKey)}`;
  const pinnedElsewhere = async (userId, deviceId) =>
    pinsOnly(await kv.all()).some((pin) => pin.deviceId === deviceId && pin.userId !== userId);
  const pinOf = (userId, deviceId, identityKey, verifiedAt, firstSeenAt = now()) => ({
    id: `${userId}/${deviceId}`,
    userId,
    deviceId,
    identityKey: encodeBase64Url(identityKey),
    firstSeenAt,
    verifiedAt,
  });

  // { verdict, verified, pin } as things stand, writing nothing: FIRST_USE
  // (pin null) for a user with no pins at all.
  async function inspect(userId, deviceId, identityKey) {
    if (await kv.get(refusalId(userId, deviceId, identityKey))) {
      return { verdict: PinVerdict.REFUSED, verified: false, pin: null };
    }
    if (await pinnedElsewhere(userId, deviceId)) return { verdict: PinVerdict.DEVICE_OF_OTHER_USER, verified: false, pin: null };
    const pins = await forUser(userId);
    const verified = pins.some((pin) => pin.verifiedAt !== null);
    const pin = pins.find((candidate) => candidate.deviceId === deviceId) ?? null;
    if (pin) {
      if (pin.identityKey !== encodeBase64Url(identityKey)) return { verdict: PinVerdict.CHANGED, verified, pin };
      const verdict = verified && pin.verifiedAt === null ? PinVerdict.UNVERIFIED_DEVICE : PinVerdict.MATCH;
      return { verdict, verified, pin };
    }
    return { verdict: pins.length > 0 ? PinVerdict.NEW_DEVICE : PinVerdict.FIRST_USE, verified, pin: null };
  }

  async function refuseOtherUsersDevice(userId, deviceId) {
    if (await pinnedElsewhere(userId, deviceId)) throw new DeviceOfOtherUserError(deviceId);
  }

  return {
    inspect,

    // inspect(), and pins the key when it reports FIRST_USE.
    check: (userId, deviceId, identityKey) => serialized(async () => {
      const result = await inspect(userId, deviceId, identityKey);
      if (result.verdict !== PinVerdict.FIRST_USE) return result;
      const fresh = pinOf(userId, deviceId, identityKey, null);
      await kv.put(fresh);
      return { ...result, pin: fresh };
    }),

    accept: (userId, deviceId, identityKey) => serialized(async () => {
      await refuseOtherUsersDevice(userId, deviceId);
      const pins = await forUser(userId);
      if (pins.some((pin) => pin.verifiedAt !== null)) throw new ReverificationRequiredError(userId);
      await kv.put(pinOf(userId, deviceId, identityKey, null));
      await kv.delete(refusalId(userId, deviceId, identityKey));
    }),

    // The user compared safety numbers for this key out of band.
    markVerified: (userId, deviceId, identityKey) => serialized(async () => {
      await refuseOtherUsersDevice(userId, deviceId);
      const existing = (await forUser(userId)).find((pin) => pin.deviceId === deviceId);
      const sameKey = existing?.identityKey === encodeBase64Url(identityKey);
      await kv.put(pinOf(userId, deviceId, identityKey, now(), sameKey ? existing.firstSeenAt : now()));
      await kv.delete(refusalId(userId, deviceId, identityKey));
    }),

    // The user declined this key for this device; it pins nothing.
    refuse: (userId, deviceId, identityKey) => serialized(() => kv.put({
      id: refusalId(userId, deviceId, identityKey),
      userId,
      deviceId,
      identityKey: encodeBase64Url(identityKey),
      refusedAt: now(),
    })),

    pinsFor: forUser,
  };
}

// The identity changes awaiting the user's decision, one per peer. They are
// kept in pendingKv (src/platform/kv.js over 'identity-pending', keyed by
// userId) as well as in memory, so a reload neither drops a change the user
// has not decided on nor needs the frame that raised it to come back; load()
// reads them back. Without pendingKv they live in memory only.
export function createIdentityTrust({ pins, pendingKv = null, onChange = () => {} }) {
  const pending = new Map(); // userId -> { deviceId, identityKey, verdict, verified }
  const presents = (change, deviceId, identityKey) =>
    change?.deviceId === deviceId && encodeBase64Url(change.identityKey) === encodeBase64Url(identityKey);

  async function record(userId, change) {
    pending.set(userId, change);
    await pendingKv?.put({ userId, ...change, identityKey: encodeBase64Url(change.identityKey) });
    onChange(userId);
  }

  async function resolve(userId) {
    pending.delete(userId);
    await pendingKv?.delete(userId);
  }

  return {
    async load() {
      pending.clear();
      for (const row of (await pendingKv?.all()) ?? []) {
        const { userId, deviceId, identityKey, verdict, verified } = row;
        pending.set(userId, { deviceId, identityKey: decodeBase64Url(identityKey), verdict, verified });
      }
    },

    // True when this key may be used for the user; otherwise records the
    // change for review, unless the key is refused outright (declined, or a
    // device of another user): then there is nothing to review.
    async admit(userId, deviceId, identityKey) {
      const { verdict, verified } = await pins.check(userId, deviceId, identityKey);
      if (verdict === PinVerdict.FIRST_USE || verdict === PinVerdict.MATCH) return true;
      if (REFUSED_OUTRIGHT.has(verdict)) return false;
      await record(userId, { deviceId, identityKey: identityKey.slice(), verdict, verified });
      return false;
    },

    // Whether this key is refused with nothing to review: the user declined
    // it, or the device is pinned under another user. Pins nothing.
    async refusesOutright(userId, deviceId, identityKey) {
      return REFUSED_OUTRIGHT.has((await pins.inspect(userId, deviceId, identityKey)).verdict);
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
      await resolve(userId);
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
      await resolve(userId);
      onChange(userId);
      return true;
    },

    async markVerified(userId, deviceId, identityKey) {
      await pins.markVerified(userId, deviceId, identityKey);
      if (presents(pending.get(userId), deviceId, identityKey)) await resolve(userId);
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

    // Forgets the changes held in memory (the session ended); the stored
    // ones stay with the identity, for load() after the next sign-in.
    reset() {
      pending.clear();
    },
  };
}
