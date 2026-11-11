// The device's session record: identity keys, handle, device id and the
// current tokens. Tokens come and go with sessions; the keys leave only when
// the caller deletes the whole record (explicit wipe or completed transfer).
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

    getAccessToken: () => record?.accessToken ?? null,
    getRefreshToken: () => record?.refreshToken ?? null,

    async saveTokens({ accessToken, refreshToken }) {
      if (!record) return;
      record.accessToken = accessToken;
      record.refreshToken = refreshToken;
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
