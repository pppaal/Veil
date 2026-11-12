// The client's single IndexedDB database. Stores:
//   session            { id: 'me', value: session record (CryptoKeys by structured clone) }
//   conversations      conversation summaries (persist.serializeConversationForCache)
//   messages           envelopes only (persist.messageCacheRecord), index byConv
//   outbound           encrypted sends awaiting retry (persist.outboundQueueEntry)
//   crypto-sessions    sealed ratchet records (src/crypto/session-repo.js)
//   one-time-prekeys   one-time prekey private keys (src/crypto/prekeys.js)
//   message-contents   decrypted contents, sealed per conversation, indexes
//                      byConversation and byExpiry (src/platform/content-store.js)
//   content-keys       the per-conversation keys those are sealed under
//   identity-pins-v2   pinned Ed25519 identity keys per (user, device), index
//                      byUser (src/crypto/pins.js)
//   identity-pending   identity changes awaiting the user's decision, keyed
//                      by userId (src/crypto/pins.js)
//   identity-pins      X25519 keys pinned before protocol v2, kept only to
//                      read that era's history (src/crypto/legacy-v1dev.js)
//   history-marks      per conversation, the conversationOrder its history
//                      has been fetched through (src/domain/history.js)
//   direct-peers       per direct conversation, the peer it was bound to
//                      once its crypto first admitted an identity for it
//                      (src/domain/peer-bindings.js)
//   kakao-archives     imported KakaoTalk archives with their messages
//   kakao-archive-meta archive rows for the sidebar, without the messages

import {
  kakaoArchiveMeta,
  sanitizeQueuedOutbound,
  serializeConversationForCache,
  serializeMessageForCache,
} from './persist.js';

export const IDB_NAME = 'veil-demo';
// v3 adds the pin and archive-meta stores and scrubs what v2 let reach disk:
// draft text, plaintext copies in the outbound queue, and decrypted fields
// (attachment keys included) spread into cached messages. v4 adds the
// protocol-v2 stores, v5 the pending identity changes and history marks, v6
// the direct conversations' peer bindings.
export const IDB_VERSION = 6;

// onBlocked: a tab on an older build holds the database open, and this
// upgrade waits until that tab closes. onDeletedElsewhere: another tab wiped
// the database; this instance refuses all further work.
export function createIdb(factory, { onBlocked, onDeletedElsewhere } = {}) {
  let connection = null;
  let deletedElsewhere = false;

  function open() {
    return new Promise((resolve, reject) => {
      const request = factory.open(IDB_NAME, IDB_VERSION);
      request.onerror = () => reject(request.error);
      request.onblocked = () => onBlocked?.();
      request.onupgradeneeded = (event) => upgrade(request.result, request.transaction, event.oldVersion);
      request.onsuccess = () => {
        const db = request.result;
        // Let a wipe or an upgrade in another tab proceed.
        db.onversionchange = (event) => {
          db.close();
          connection = null;
          // newVersion is null for a delete. Reopening would recreate the
          // database from what this tab still holds in memory (its session
          // record and keys included) and undo the other tab's wipe.
          if (event.newVersion === null) {
            deletedElsewhere = true;
            onDeletedElsewhere?.();
          }
        };
        resolve(db);
      };
    });
  }

  async function connect() {
    if (deletedElsewhere) throw new Error('database deleted by another tab');
    connection ??= open().catch((error) => {
      connection = null;
      throw error;
    });
    return connection;
  }

  async function run(storeName, mode, operation) {
    const db = await connect();
    return new Promise((resolve, reject) => {
      const request = operation(db.transaction(storeName, mode).objectStore(storeName));
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => reject(request.error);
    });
  }

  return {
    get: async (store, key) => (await run(store, 'readonly', (s) => s.get(key))) ?? null,
    allByIndex: async (store, index, value) =>
      (await run(store, 'readonly', (s) => s.index(index).getAll(value))) ?? [],
    allByIndexUpTo: async (store, index, upper) =>
      (await run(store, 'readonly', (s) => s.index(index).getAll(IDBKeyRange.upperBound(upper)))) ?? [],
    put: async (store, value) => { await run(store, 'readwrite', (s) => s.put(value)); },
    // Reads, transforms and writes one row in a single transaction, so a
    // writer in another tab lands wholly before or after it and neither
    // reverts the other's fields. transform(row | null) returns the row to
    // write, or null to leave the store as it is; resolves to that result.
    async modify(storeName, key, transform) {
      const db = await connect();
      return new Promise((resolve, reject) => {
        const transaction = db.transaction(storeName, 'readwrite');
        const store = transaction.objectStore(storeName);
        let next = null;
        let failure = null;
        const read = store.get(key);
        read.onsuccess = () => {
          try {
            next = transform(read.result ?? null);
            if (next !== null) store.put(next);
          } catch (error) {
            failure = error;
            transaction.abort();
          }
        };
        transaction.oncomplete = () => resolve(next);
        transaction.onabort = () => reject(failure ?? transaction.error ?? new Error('transaction aborted'));
      });
    },
    delete: async (store, key) => { await run(store, 'readwrite', (s) => s.delete(key)); },
    all: async (store) => (await run(store, 'readonly', (s) => s.getAll())) ?? [],
    // Empties every store but the kept ones, in one transaction. A completed
    // device transfer replaces the stored identity this way: it overwrites
    // the session record and clears the rest, stores added later included,
    // as deleting the database would, but without a delete that another tab
    // can hold up and that would take the new record with it.
    async clearAllExcept(keptStores) {
      const db = await connect();
      const names = Array.from(db.objectStoreNames).filter((name) => !keptStores.includes(name));
      if (names.length === 0) return;
      await new Promise((resolve, reject) => {
        const transaction = db.transaction(names, 'readwrite');
        for (const name of names) transaction.objectStore(name).clear();
        transaction.oncomplete = () => resolve();
        // A failed clear aborts the whole transaction: nothing is half cleared.
        transaction.onabort = () => reject(transaction.error ?? new Error('clear aborted'));
      });
    },
    async close() {
      const pending = connection;
      connection = null;
      const db = await pending?.catch(() => null);
      db?.close();
    },
  };
}

function upgrade(db, transaction, oldVersion) {
  ensureStore(db, 'session', 'id');
  ensureStore(db, 'conversations', 'id');
  if (!db.objectStoreNames.contains('messages')) {
    db.createObjectStore('messages', { keyPath: '_key' }).createIndex('byConv', 'conversationId', { unique: false });
  }
  ensureStore(db, 'outbound', 'clientMessageId');
  ensureStore(db, 'kakao-archives', 'id');
  ensureStore(db, 'kakao-archive-meta', 'id');
  ensureStore(db, 'identity-pins', 'userId');
  ensureStore(db, 'crypto-sessions', 'conversationId');
  ensureStore(db, 'one-time-prekeys', 'keyId');
  ensureStore(db, 'content-keys', 'conversationId');
  ensureStore(db, 'message-contents', 'key', {
    indexes: [['byConversation', 'conversationId'], ['byExpiry', 'expiresAt']],
  });
  ensureStore(db, 'identity-pins-v2', 'id', { indexes: [['byUser', 'userId']] });
  ensureStore(db, 'identity-pending', 'userId');
  ensureStore(db, 'history-marks', 'conversationId');
  ensureStore(db, 'direct-peers', 'conversationId');
  if (oldVersion > 0 && oldVersion < 3) scrubVersion2(db, transaction);
}

function scrubVersion2(db, transaction) {
  if (db.objectStoreNames.contains('drafts')) db.deleteObjectStore('drafts');
  rewriteEach(transaction.objectStore('outbound'), sanitizeQueuedOutbound);
  rewriteEach(transaction.objectStore('messages'), (row) => ({ _key: row._key, ...serializeMessageForCache(row) }));
  rewriteEach(transaction.objectStore('conversations'), serializeConversationForCache);
  const meta = transaction.objectStore('kakao-archive-meta');
  forEachRecord(transaction.objectStore('kakao-archives'), (archive) => meta.put(kakaoArchiveMeta(archive)));
}

function ensureStore(db, name, keyPath, { indexes = [] } = {}) {
  if (db.objectStoreNames.contains(name)) return;
  const store = db.createObjectStore(name, { keyPath });
  for (const [indexName, indexKeyPath] of indexes) store.createIndex(indexName, indexKeyPath, { unique: false });
}

function rewriteEach(store, transform) {
  store.openCursor().onsuccess = (event) => {
    const cursor = event.target.result;
    if (!cursor) return;
    cursor.update(transform(cursor.value));
    cursor.continue();
  };
}

function forEachRecord(store, visit) {
  store.openCursor().onsuccess = (event) => {
    const cursor = event.target.result;
    if (!cursor) return;
    visit(cursor.value);
    cursor.continue();
  };
}
