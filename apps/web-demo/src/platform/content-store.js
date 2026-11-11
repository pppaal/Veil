// Decrypted message contents, kept so that each ciphertext is decrypted
// exactly once: protocol-v2 message keys are single-use, and rendering reads
// only from here. Two IndexedDB stores:
//   message-contents  { key: conversationId/id, conversationId, id, expiresAt, nonce, sealed }
//                     or, once retired, { key, conversationId, id, retired: true }
//   content-keys      { conversationId, key }
// Each conversation has its own non-extractable AES-256-GCM key, and a
// record is sealed with AAD "message-contents" || id, so a record copied to
// another id does not open. Deleting a conversation's key crypto-shreds all
// of its records at once, whatever copies of the rows survive.
//
// A message that was deleted or has expired is retired: its sealed content
// is overwritten by a marker that only says so. Its message key is spent,
// so a relay that serves it again gets it hidden rather than shown as a
// failure, and nothing written later brings the content back: writes to a
// row run one at a time, so a put that was sealing while the row was
// retired finds the marker and stops. expiresAt
// (ms, contract C4) stays in the clear, so that expired records can be
// found and retired without opening any; it says no more than the relay's
// own expiry for the message.

import { earlierExpiry } from '../core/expiry.js';
import { concatBytes, fromUtf8, utf8 } from '../crypto/bytes.js';
import { GCM_NONCE_BYTES, gcmParams, generateStorageKey } from '../crypto/keys.js';

const AAD_LABEL = utf8('message-contents');
// What get() returns for a retired message.
const RETIRED = Object.freeze({ retired: true });

const rowKey = (conversationId, id) => `${conversationId}/${id}`;
const aad = (id) => concatBytes([AAD_LABEL, utf8(id)]);

// records: kv with keyPath 'key', indexed by conversationId and by expiresAt
// (dueBy); keys: kv with keyPath 'conversationId' (src/platform/kv.js).
// locks serializes key creation and each row's read-then-write across tabs
// (src/crypto/locks.js).
export function createContentStore({ subtle, random, records, keys, locks }) {
  const withRow = (conversationId, id, task) => locks.run(`veil-content:${rowKey(conversationId, id)}`, task);

  async function existingKey(conversationId) {
    return (await keys.get(conversationId))?.key ?? null;
  }

  function keyFor(conversationId) {
    return locks.run(`veil-content-key:${conversationId}`, async () => {
      const existing = await existingKey(conversationId);
      if (existing) return existing;
      const key = await generateStorageKey(subtle);
      await keys.put({ conversationId, key });
      return key;
    });
  }

  // A record's expiry only ever comes earlier: rewriting it (an edit, a
  // move) keeps the one it had.
  function put(conversationId, id, value, { expiresAt = null } = {}) {
    return withRow(conversationId, id, async () => {
      const existing = await records.get(rowKey(conversationId, id));
      if (existing?.retired) return;
      const key = await keyFor(conversationId);
      const nonce = random(GCM_NONCE_BYTES);
      const plain = utf8(JSON.stringify(value));
      const sealed = new Uint8Array(await subtle.encrypt(gcmParams(nonce, aad(id)), key, plain));
      plain.fill(0);
      await records.put({
        key: rowKey(conversationId, id),
        conversationId,
        id,
        expiresAt: earlierExpiry(existing?.expiresAt, expiresAt),
        nonce,
        sealed,
      });
    });
  }

  // RETIRED for a retired message; null when nothing is stored, the
  // conversation's key is gone, or the record does not authenticate under
  // this id.
  async function unseal(conversationId, id, row) {
    if (row.retired) return RETIRED;
    const key = await existingKey(conversationId);
    if (!key) return null;
    try {
      const plain = await subtle.decrypt(gcmParams(row.nonce, aad(id)), key, row.sealed);
      return JSON.parse(fromUtf8(new Uint8Array(plain)));
    } catch {
      return null;
    }
  }

  async function get(conversationId, id) {
    const row = await records.get(rowKey(conversationId, id));
    return row ? unseal(conversationId, id, row) : null;
  }

  function retire(conversationId, id) {
    return withRow(conversationId, id, async () => {
      const key = rowKey(conversationId, id);
      if ((await records.get(key))?.retired) return;
      await records.put({ key, conversationId, id, retired: true });
    });
  }

  return {
    put,
    get,
    retire,

    // Every record whose expiry is at or before `now`, loaded or not.
    async retireExpired(now) {
      for (const row of await records.dueBy(now)) await retire(row.conversationId, row.id);
    },

    // expiresAt: an expiry learned since the record was written (the
    // relay's, once it has named the message).
    async move(conversationId, fromId, toId, { expiresAt = null } = {}) {
      const row = await records.get(rowKey(conversationId, fromId));
      if (!row) return;
      if (row.retired) {
        await retire(conversationId, toId);
      } else {
        const value = await unseal(conversationId, fromId, row);
        if (value === null) return;
        await put(conversationId, toId, value, { expiresAt: earlierExpiry(row.expiresAt, expiresAt) });
      }
      await records.delete(row.key);
    },

    delete: (conversationId, id) => records.delete(rowKey(conversationId, id)),

    // The key goes first: once it is deleted nothing left behind opens.
    async deleteConversation(conversationId) {
      await keys.delete(conversationId);
      for (const row of await records.byIndex(conversationId)) await records.delete(row.key);
    },
  };
}
