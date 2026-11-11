// The client's single IndexedDB database. Stores:
//   session            { id: 'me', value: session record (CryptoKeys by structured clone) }
//   conversations      conversation summaries (persist.serializeConversationForCache)
//   messages           envelopes only (persist.messageCacheRecord), index byConv
//   outbound           encrypted sends awaiting retry (persist.outboundQueueEntry)
//   identity-pins      { userId, peerKey, firstSeenAt }
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
// (attachment keys included) spread into cached messages.
export const IDB_VERSION = 3;

export function createIdb(factory) {
  let connection = null;

  function open() {
    return new Promise((resolve, reject) => {
      const request = factory.open(IDB_NAME, IDB_VERSION);
      request.onerror = () => reject(request.error);
      request.onupgradeneeded = (event) => upgrade(request.result, request.transaction, event.oldVersion);
      request.onsuccess = () => {
        const db = request.result;
        // Let a wipe or an upgrade in another tab proceed.
        db.onversionchange = () => {
          db.close();
          connection = null;
        };
        resolve(db);
      };
    });
  }

  async function run(storeName, mode, operation) {
    connection ??= open().catch((error) => {
      connection = null;
      throw error;
    });
    const db = await connection;
    return new Promise((resolve, reject) => {
      const request = operation(db.transaction(storeName, mode).objectStore(storeName));
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => reject(request.error);
    });
  }

  return {
    get: async (store, key) => (await run(store, 'readonly', (s) => s.get(key))) ?? null,
    put: async (store, value) => { await run(store, 'readwrite', (s) => s.put(value)); },
    delete: async (store, key) => { await run(store, 'readwrite', (s) => s.delete(key)); },
    all: async (store) => (await run(store, 'readonly', (s) => s.getAll())) ?? [],
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

function ensureStore(db, name, keyPath) {
  if (!db.objectStoreNames.contains(name)) db.createObjectStore(name, { keyPath });
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
