// The device's session record: identity keys, prekey state, handle, device
// id and the current tokens. Tokens come and go with sessions; the keys leave
// only when the caller deletes the whole record (explicit wipe, or a
// completed transfer on the old device) or saves another identity over it (a
// transfer completing on this device).
// The record object is kept and mutated in place so the app can hold a
// reference to it as the signed-in identity.
//
// Every tab of the origin holds its own copy of the one stored record, and
// several of them write it: token renewals in any tab, prekey maintenance in
// whichever tab holds PREKEY_LOCK. A tab's copy is stale as soon as another
// tab writes, so no write puts it back whole. Each merges only the fields it
// changes into the record as stored at that moment, in one atomic
// read-modify-write; otherwise a token renewal would revert the one-time
// prekey counter or drop a rotated signed prekey's private key.
//
// repo: { get() -> record | null, put(record),
//         modify(transform) -> what transform returned }, where
// transform(stored | null) returns the record to store, or null to store
// nothing, and no other write can land between its read and its write.

import { migrateStoredIdentity, signChallenge } from '../crypto/identity.js';

// The auth key is the one key every identity, legacy or v2, has and no two
// identities share.
const isSameIdentity = (stored, held) => stored !== null && stored.edPubB64u === held.edPubB64u;

// The repo over the record's row in IndexedDB (src/platform/idb.js).
// readLegacy() supplies a record kept from before that row existed.
export function createIdbSessionRepo(idb, { readLegacy = async () => null } = {}) {
  const row = (value) => ({ id: 'me', value });
  return {
    async get() {
      return (await idb.get('session', 'me'))?.value ?? readLegacy();
    },
    put: (value) => idb.put('session', row(value)),
    async modify(transform) {
      const written = await idb.modify('session', 'me', (stored) => {
        const value = transform(stored?.value ?? null);
        return value === null ? null : row(value);
      });
      return written?.value ?? null;
    },
  };
}

export function createSessionStore({ repo, subtle }) {
  let record = null;

  // A write is for the identity this tab holds. Once another tab replaced
  // that identity (a device transfer) or deleted it, nothing is written:
  // this tab's tokens and prekeys mean nothing to the stored one.
  async function patch(fields) {
    if (!record) return;
    const held = Object.assign(record, fields);
    await repo.modify((stored) => (isSameIdentity(stored, held) ? { ...stored, ...fields } : null));
  }

  return {
    current: () => record,

    async load() {
      const stored = await repo.get();
      if (!stored) {
        record = null;
        return null;
      }
      const { record: migrated, changed } = await migrateStoredIdentity(stored, subtle);
      if (changed) await repo.put(migrated);
      record = migrated;
      return record;
    },

    async save(next) {
      await repo.put(next);
      record = next;
    },

    // Prekey rotation and replenishment (src/crypto/prekeys.js) change the
    // identity's prekey fields.
    update: patch,

    // Another tab may have rotated prekeys or renewed tokens since this one
    // loaded the record; the stored fields are merged into the same object,
    // which the app holds as the signed-in identity. Another identity's
    // fields never are.
    async reload() {
      const stored = record ? await repo.get() : null;
      if (stored && isSameIdentity(stored, record)) Object.assign(record, stored);
      return record;
    },

    getAccessToken: () => record?.accessToken ?? null,
    getRefreshToken: () => record?.refreshToken ?? null,

    // A login also names the user this device belongs to. A transferred
    // device's record is saved before its first login, so its userId arrives
    // here, and a record whose first login failed is repaired by the next.
    saveTokens({ accessToken, refreshToken, userId }) {
      const named = typeof userId === 'string' && userId ? { userId } : {};
      return patch({ accessToken, refreshToken, ...named });
    },

    clearTokens: () => patch({ accessToken: null, refreshToken: null }),

    async getDeviceCredentials() {
      if (!record?.edPrivKey || !record.handle || !record.deviceId) return null;
      const { handle, deviceId, edPrivKey } = record;
      return { handle, deviceId, sign: (challenge) => signChallenge(subtle, edPrivKey, challenge) };
    },

    // Drops the in-memory reference after the stored record was destroyed.
    forget() {
      record = null;
    },
  };
}
