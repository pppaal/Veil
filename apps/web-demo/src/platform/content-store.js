// Decrypted message contents, kept so that each ciphertext is decrypted
// exactly once: protocol-v2 message keys are single-use, and rendering reads
// only from here. Two IndexedDB stores:
//   message-contents  { key: conversationId/id, conversationId, id, nonce, sealed }
//   content-keys      { conversationId, key }
// Each conversation has its own non-extractable AES-256-GCM key, and a
// record is sealed with AAD "message-contents" || id, so a record copied to
// another id does not open. Deleting a conversation's key crypto-shreds all
// of its records at once, whatever copies of the rows survive.

import { concatBytes, fromUtf8, utf8 } from '../crypto/bytes.js';
import { GCM_NONCE_BYTES, gcmParams, generateStorageKey } from '../crypto/keys.js';

const AAD_LABEL = utf8('message-contents');

const rowKey = (conversationId, id) => `${conversationId}/${id}`;
const aad = (id) => concatBytes([AAD_LABEL, utf8(id)]);

// records: kv with keyPath 'key' indexed by conversationId; keys: kv with
// keyPath 'conversationId' (src/platform/kv.js). locks serializes key
// creation across tabs (src/crypto/locks.js).
export function createContentStore({ subtle, random, records, keys, locks }) {
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

  async function put(conversationId, id, value) {
    const key = await keyFor(conversationId);
    const nonce = random(GCM_NONCE_BYTES);
    const plain = utf8(JSON.stringify(value));
    const sealed = new Uint8Array(await subtle.encrypt(gcmParams(nonce, aad(id)), key, plain));
    plain.fill(0);
    await records.put({ key: rowKey(conversationId, id), conversationId, id, nonce, sealed });
  }

  // null when nothing is stored, the conversation's key is gone, or the
  // record does not authenticate under this id.
  async function get(conversationId, id) {
    const row = await records.get(rowKey(conversationId, id));
    const key = row ? await existingKey(conversationId) : null;
    if (!key) return null;
    try {
      const plain = await subtle.decrypt(gcmParams(row.nonce, aad(id)), key, row.sealed);
      return JSON.parse(fromUtf8(new Uint8Array(plain)));
    } catch {
      return null;
    }
  }

  return {
    put,
    get,

    async move(conversationId, fromId, toId) {
      const value = await get(conversationId, fromId);
      if (value === null) return;
      await put(conversationId, toId, value);
      await records.delete(rowKey(conversationId, fromId));
    },

    delete: (conversationId, id) => records.delete(rowKey(conversationId, id)),

    // The key goes first: once it is deleted nothing left behind opens.
    async deleteConversation(conversationId) {
      await keys.delete(conversationId);
      for (const row of await records.byIndex(conversationId)) await records.delete(row.key);
    },
  };
}
