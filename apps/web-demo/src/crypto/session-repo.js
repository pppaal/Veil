// Durable session records ('crypto-sessions'). A row is
//   { conversationId, rev, nonce, sealed, keys }
// where `keys` are the ratchet private keys as non-extractable CryptoKeys
// (stored by structured clone) and `sealed` is everything else - roots,
// chains, skipped message keys - as AES-256-GCM under a non-extractable KEK
// with AAD "crypto-sessions" || conversationId, so a row copied to another
// conversation does not open.
//
// Writes are compare-and-swap on `rev`: a caller passes the rev it loaded,
// and a row that moved on since is refused rather than overwritten, so an
// operation fails instead of publishing state that is not on disk. `rev`
// survives a row whose sealed part no longer opens, so even then it only
// grows. The check and the write are separate transactions, so the swap is
// atomic only under the conversation lock (src/crypto/locks.js): across tabs
// that takes navigator.locks, which every browser this demo supports has;
// the in-tab fallback serializes this tab alone.
//
// The storage behind the repository is a key-value store
// (src/platform/kv.js: IndexedDB or in-memory).

import { concatBytes, fromUtf8, utf8 } from './bytes.js';
import { GCM_NONCE_BYTES, gcmParams } from './keys.js';
import { SessionRecord } from './session-record.js';

const AAD_LABEL = utf8('crypto-sessions');

class StaleSessionWriteError extends Error {
  constructor(conversationId) {
    super(`session for ${conversationId} changed since it was read`);
    this.name = 'StaleSessionWriteError';
  }
}

// kv: { get(conversationId) -> row | null, put(row) }
export function createSessionRepo({ subtle, random, getKek, kv, clock }) {
  const aad = (conversationId) => concatBytes([AAD_LABEL, utf8(conversationId)]);

  async function open(row) {
    try {
      const plain = await subtle.decrypt(gcmParams(row.nonce, aad(row.conversationId)), await getKek(), row.sealed);
      return SessionRecord.fromSnapshot(JSON.parse(fromUtf8(new Uint8Array(plain))), row.keys, clock());
    } catch {
      return null;
    }
  }

  return {
    // { rev, record }: rev 0 and no record when nothing is stored; a stored
    // row that does not open yields its rev and no record, so the caller
    // re-bootstraps instead of crashing.
    async load(conversationId) {
      const row = await kv.get(conversationId);
      if (!row) return { rev: 0, record: null };
      return { rev: row.rev, record: await open(row) };
    },

    async save(conversationId, record, baseRev) {
      const stored = await kv.get(conversationId);
      if ((stored?.rev ?? 0) !== baseRev) throw new StaleSessionWriteError(conversationId);
      const keys = [];
      const snapshot = record.toSnapshot(keys);
      const nonce = random(GCM_NONCE_BYTES);
      const plain = utf8(JSON.stringify(snapshot));
      const sealed = new Uint8Array(await subtle.encrypt(gcmParams(nonce, aad(conversationId)), await getKek(), plain));
      plain.fill(0);
      await kv.put({ conversationId, rev: baseRev + 1, nonce, sealed, keys });
    },
  };
}
