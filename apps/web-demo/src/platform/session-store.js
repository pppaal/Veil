// The device's session record: identity keys, handle, device id and the
// current tokens. Tokens come and go with sessions; the keys leave only when
// the caller deletes the whole record (explicit wipe, or a completed transfer
// on the old device) or saves another identity over it (a transfer
// completing on this device).
// The record object is kept and mutated in place so the app can hold a
// reference to it as the signed-in identity.

import { migrateStoredIdentity, signChallenge } from '../crypto/identity.js';

export function createSessionStore({ repo, subtle }) {
  let record = null;

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
    // identity's key fields in place.
    async update(fields) {
      if (!record) return;
      Object.assign(record, fields);
      await repo.put(record);
    },

    // Another tab may have rotated prekeys or renewed tokens since this one
    // loaded the record; the stored fields are merged into the same object,
    // which the app holds as the signed-in identity.
    async reload() {
      const stored = record ? await repo.get() : null;
      if (stored) Object.assign(record, stored);
      return record;
    },

    getAccessToken: () => record?.accessToken ?? null,
    getRefreshToken: () => record?.refreshToken ?? null,

    // A login also names the user this device belongs to. A transferred
    // device's record is saved before its first login, so its userId arrives
    // here, and a record whose first login failed is repaired by the next.
    async saveTokens({ accessToken, refreshToken, userId }) {
      if (!record) return;
      record.accessToken = accessToken;
      record.refreshToken = refreshToken;
      if (typeof userId === 'string' && userId) record.userId = userId;
      await repo.put(record);
    },

    async clearTokens() {
      if (!record) return;
      record.accessToken = null;
      record.refreshToken = null;
      await repo.put(record);
    },

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
