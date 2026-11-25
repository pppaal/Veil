import { describe, expect, it, vi } from 'vitest';

import { createIdb, IDB_NAME, IDB_VERSION } from '../src/platform/idb.js';

// IDBFactory double: every open succeeds asynchronously with a database whose
// stores answer from one shared map. `blocked` makes the next open report
// that another tab is holding up the upgrade before it succeeds.
function fakeIndexedDb() {
  const rows = new Map();
  const databases = [];
  const answer = (result) => {
    const request = {};
    queueMicrotask(() => {
      request.result = result;
      request.onsuccess?.();
    });
    return request;
  };
  const store = {
    get: (key) => answer(rows.get(key)),
    put: (value) => {
      rows.set(value.id, value);
      return answer(value.id);
    },
  };
  const factory = {
    blocked: false,
    open: vi.fn((name, version) => {
      expect([name, version]).toEqual([IDB_NAME, IDB_VERSION]);
      const db = { close: vi.fn(), transaction: () => ({ objectStore: () => store }) };
      databases.push(db);
      const request = {};
      const blocked = factory.blocked;
      queueMicrotask(() => {
        if (blocked) request.onblocked?.();
        request.result = db;
        request.onsuccess?.();
      });
      return request;
    }),
  };
  return { factory, databases, rows };
}

describe('createIdb', () => {
  it('stops all work once another tab deletes the database', async () => {
    const { factory, databases, rows } = fakeIndexedDb();
    const onDeletedElsewhere = vi.fn();
    const idb = createIdb(factory, { onDeletedElsewhere });
    await idb.put('session', { id: 'me', value: 'keys' });

    databases[0].onversionchange({ newVersion: null });

    expect(databases[0].close).toHaveBeenCalledTimes(1);
    expect(onDeletedElsewhere).toHaveBeenCalledTimes(1);
    rows.clear();
    // Writing now would recreate the wiped database with this tab's keys.
    await expect(idb.put('session', { id: 'me', value: 'keys' })).rejects.toThrow('deleted by another tab');
    await expect(idb.get('session', 'me')).rejects.toThrow('deleted by another tab');
    expect(factory.open).toHaveBeenCalledTimes(1);
    expect(rows.size).toBe(0);
  });

  it('closes for an upgrade in another tab and reopens on the next use', async () => {
    const { factory, databases } = fakeIndexedDb();
    const onDeletedElsewhere = vi.fn();
    const idb = createIdb(factory, { onDeletedElsewhere });
    await idb.put('session', { id: 'me', value: 'keys' });

    databases[0].onversionchange({ newVersion: IDB_VERSION + 1 });

    expect(databases[0].close).toHaveBeenCalledTimes(1);
    expect(onDeletedElsewhere).not.toHaveBeenCalled();
    expect(await idb.get('session', 'me')).toEqual({ id: 'me', value: 'keys' });
    expect(factory.open).toHaveBeenCalledTimes(2);
  });

  it('reports an upgrade held up by a tab on an older build', async () => {
    const { factory } = fakeIndexedDb();
    factory.blocked = true;
    const onBlocked = vi.fn();
    const idb = createIdb(factory, { onBlocked });

    expect(await idb.get('session', 'me')).toBeNull();
    expect(onBlocked).toHaveBeenCalledTimes(1);
  });
});

// IDBFactory double for a database with the given stores, each holding one
// row. A readwrite transaction applies its clears when it commits, or none of
// them when `abort` is set.
function storesIndexedDb(names, { abort = false } = {}) {
  const rows = new Map(names.map((name) => [name, new Map([['row', { id: 'row' }]])]));
  const transactions = [];
  const db = {
    objectStoreNames: names,
    close: vi.fn(),
    transaction(storeNames, mode) {
      const cleared = [];
      const transaction = {
        storeNames,
        mode,
        objectStore: (name) => ({ clear: () => { cleared.push(name); } }),
      };
      transactions.push(transaction);
      queueMicrotask(() => {
        if (abort) {
          transaction.error = new DOMException('quota exceeded', 'QuotaExceededError');
          transaction.onabort();
          return;
        }
        for (const name of cleared) rows.get(name).clear();
        transaction.oncomplete();
      });
      return transaction;
    },
  };
  const factory = {
    open: vi.fn(() => {
      const request = {};
      queueMicrotask(() => {
        request.result = db;
        request.onsuccess();
      });
      return request;
    }),
  };
  return { factory, rows, transactions };
}

describe('clearAllExcept', () => {
  const STORES = ['session', 'conversations', 'messages', 'outbound', 'identity-pins', 'kakao-archives'];

  it('empties every other store in one transaction and keeps the named ones', async () => {
    const { factory, rows, transactions } = storesIndexedDb(STORES);

    await createIdb(factory).clearAllExcept(['session']);

    expect(transactions).toHaveLength(1);
    expect(transactions[0].mode).toBe('readwrite');
    expect(transactions[0].storeNames).toEqual(STORES.slice(1));
    expect(rows.get('session').size).toBe(1);
    for (const name of STORES.slice(1)) expect(rows.get(name).size).toBe(0);
  });

  it('rejects, with nothing cleared, when the transaction aborts', async () => {
    const { factory, rows } = storesIndexedDb(STORES, { abort: true });

    await expect(createIdb(factory).clearAllExcept(['session'])).rejects.toThrow('quota exceeded');
    for (const name of STORES) expect(rows.get(name).size).toBe(1);
  });
});

// IDBFactory double for one store whose readwrite transactions apply their
// writes when they commit, after the requests made in them have settled,
// and none of them when aborted.
function rowIndexedDb(initial) {
  const rows = new Map(Object.entries(initial));
  const transactions = [];
  const db = {
    close: vi.fn(),
    transaction(storeName, mode) {
      const writes = [];
      let pending = 0;
      let aborted = false;
      const transaction = {
        storeName,
        mode,
        abort() {
          aborted = true;
          transaction.error = new DOMException('aborted', 'AbortError');
        },
        objectStore: () => ({
          get(key) {
            const request = {};
            pending += 1;
            queueMicrotask(() => {
              request.result = rows.get(key);
              request.onsuccess();
              pending -= 1;
              if (pending === 0) settle();
            });
            return request;
          },
          put(row) {
            writes.push(row);
          },
        }),
      };
      const settle = () => {
        if (aborted) return transaction.onabort();
        for (const row of writes) rows.set(row.id, row);
        transaction.oncomplete();
      };
      transactions.push(transaction);
      return transaction;
    },
  };
  const factory = {
    open: vi.fn(() => {
      const request = {};
      queueMicrotask(() => {
        request.result = db;
        request.onsuccess();
      });
      return request;
    }),
  };
  return { factory, rows, transactions };
}

describe('modify', () => {
  it('reads, transforms and writes a row in one readwrite transaction', async () => {
    const { factory, rows, transactions } = rowIndexedDb({ me: { id: 'me', value: { a: 1, b: 1 } } });
    const idb = createIdb(factory);

    const written = await idb.modify('session', 'me', (row) => ({ ...row, value: { ...row.value, b: 2 } }));

    expect(written).toEqual({ id: 'me', value: { a: 1, b: 2 } });
    expect(rows.get('me')).toEqual(written);
    expect(transactions.map(({ storeName, mode }) => [storeName, mode])).toEqual([['session', 'readwrite']]);
  });

  it('writes nothing when the transform returns null or throws', async () => {
    const { factory, rows } = rowIndexedDb({});
    const idb = createIdb(factory);

    expect(await idb.modify('session', 'me', (row) => (row === null ? null : { id: 'me' }))).toBeNull();
    const failure = new Error('cannot merge');
    await expect(idb.modify('session', 'me', () => { throw failure; })).rejects.toBe(failure);
    expect(rows.size).toBe(0);
  });
});

// A version 2 database as the pre-hardening app.js left it, behind an
// IDBFactory double that runs the upgrade (stores, cursors, update) and opens
// once the upgrade's cursor walks have finished.
function versionTwoIndexedDb(stores, { oldVersion = 2 } = {}) {
  const data = new Map(Object.entries(stores).map(([name, { keyPath, rows }]) => (
    [name, { keyPath, rows: new Map(rows.map((row) => [row[keyPath], row])) }]
  )));
  const answer = (result) => {
    const request = {};
    queueMicrotask(() => {
      request.result = result;
      request.onsuccess?.();
    });
    return request;
  };
  const objectStore = (name) => {
    const store = data.get(name);
    return {
      put: (value) => {
        store.rows.set(value[store.keyPath], value);
        return answer(value[store.keyPath]);
      },
      getAll: () => answer([...store.rows.values()]),
      openCursor() {
        const request = {};
        const keys = [...store.rows.keys()];
        let index = 0;
        const step = () => queueMicrotask(() => {
          const key = keys[index];
          const cursor = key === undefined ? null : {
            value: store.rows.get(key),
            update(value) {
              expect(value[store.keyPath]).toBe(key);
              store.rows.set(key, value);
            },
            continue() {
              index += 1;
              step();
            },
          };
          request.onsuccess({ target: { result: cursor } });
        });
        step();
        return request;
      },
    };
  };
  const db = {
    objectStoreNames: { contains: (name) => data.has(name) },
    createObjectStore(name, { keyPath }) {
      data.set(name, { keyPath, rows: new Map() });
      return { createIndex: vi.fn() };
    },
    deleteObjectStore: (name) => data.delete(name),
    transaction: (name) => ({ objectStore: () => objectStore(name) }),
    close: vi.fn(),
  };
  const factory = {
    open: vi.fn(() => {
      const request = {};
      queueMicrotask(() => {
        request.result = db;
        request.transaction = { objectStore };
        request.onupgradeneeded({ oldVersion });
        setTimeout(() => request.onsuccess(), 0);
      });
      return request;
    }),
  };
  return { factory, data };
}

describe('upgrade from version 2', () => {
  it('scrubs drafts, queued plaintext and decrypted fields from what v2 left on disk', async () => {
    const message = {
      _key: 'c-1:4',
      id: 'm-4',
      conversationId: 'c-1',
      senderDeviceId: 'd-peer',
      conversationOrder: 4,
      ciphertext: 'v2.sealed',
      nonce: 'n-4',
      version: 'veil-envelope-v1-dev',
      messageType: 'file',
      serverReceivedAt: '2026-11-01T09:00:00.000Z',
      deletedAt: null,
      clientMessageId: 'file-1',
      attachment: { attachmentId: 'a-1', encryption: { key: 'ATTACHMENT-KEY', nonce: 'a-n' } },
      _fileMeta: { name: 'contract.pdf', key: 'ATTACHMENT-KEY', nonce: 'a-n' },
      _replyTo: 'm-3',
      _imageUrl: 'blob:https://veil/1',
    };
    const { factory, data } = versionTwoIndexedDb({
      session: { keyPath: 'id', rows: [{ id: 'me', value: { handle: 'alice' } }] },
      conversations: {
        keyPath: 'id',
        rows: [{
          id: 'c-1',
          type: 'direct',
          createdAt: '2026-11-01T08:00:00.000Z',
          members: [{ userId: 'u-1', handle: 'alice', displayName: 'Alice', lastReadAt: 'x' }],
          lastMessage: { ...message, _plaintext: 'DECRYPTED PREVIEW' },
          _unread: 3,
        }],
      },
      messages: { keyPath: '_key', rows: [message] },
      outbound: {
        keyPath: 'clientMessageId',
        rows: [{
          clientMessageId: 'web-9',
          conversationId: 'c-1',
          envelope: { version: 'veil-envelope-v1-dev', conversationId: 'c-1', ciphertext: 'v2.q', nonce: 'n-9', messageType: 'text' },
          plaintext: 'QUEUED PLAINTEXT',
          attempts: 2,
          nextRetryAt: 5,
        }],
      },
      drafts: { keyPath: 'convId', rows: [{ convId: 'c-1', text: 'DRAFT TEXT' }] },
      'kakao-archives': {
        keyPath: 'id',
        rows: [{ id: 'kakao-1', title: 'Family', importedAt: '2026-10-01', messageCount: 1, messages: [{ text: 'ARCHIVED' }] }],
      },
    });
    const idb = createIdb(factory);

    expect(await idb.all('messages')).toEqual([{
      _key: 'c-1:4',
      id: 'm-4',
      conversationId: 'c-1',
      senderDeviceId: 'd-peer',
      conversationOrder: 4,
      ciphertext: 'v2.sealed',
      nonce: 'n-4',
      version: 'veil-envelope-v1-dev',
      messageType: 'file',
      serverReceivedAt: '2026-11-01T09:00:00.000Z',
      deletedAt: null,
    }]);
    expect(await idb.all('outbound')).toEqual([{
      clientMessageId: 'web-9',
      conversationId: 'c-1',
      envelope: { version: 'veil-envelope-v1-dev', conversationId: 'c-1', ciphertext: 'v2.q', nonce: 'n-9', messageType: 'text' },
      attempts: 2,
      nextRetryAt: 5,
    }]);
    const [conversation] = await idb.all('conversations');
    expect(conversation.members).toEqual([{ userId: 'u-1', handle: 'alice' }]);
    expect(conversation).not.toHaveProperty('_unread');
    expect(await idb.all('kakao-archive-meta'))
      .toEqual([{ id: 'kakao-1', title: 'Family', importedAt: '2026-10-01', messageCount: 1 }]);
    expect(data.has('drafts')).toBe(false);
    expect(data.has('identity-pins')).toBe(true);

    const disk = JSON.stringify([...data.entries()].map(([name, store]) => [name, [...store.rows.values()]]));
    for (const secret of ['ATTACHMENT-KEY', 'DECRYPTED PREVIEW', 'QUEUED PLAINTEXT', 'DRAFT TEXT', 'blob:']) {
      expect(disk).not.toContain(secret);
    }
    // The archive itself keeps its messages; only the sidebar copy drops them.
    expect(disk).toContain('ARCHIVED');
  });
});

describe('upgrade from version 5', () => {
  it('adds the peer bindings and leaves every other store as it was', async () => {
    const v5Stores = {
      session: { keyPath: 'id', rows: [{ id: 'me', value: { handle: 'alice' } }] },
      conversations: { keyPath: 'id', rows: [{ id: 'c-1', type: 'direct', members: [{ userId: 'u-1', handle: 'alice' }] }] },
      messages: { keyPath: '_key', rows: [{ _key: 'c-1:1', id: 'm-1', conversationId: 'c-1', conversationOrder: 1 }] },
      outbound: { keyPath: 'clientMessageId', rows: [] },
      'kakao-archives': { keyPath: 'id', rows: [] },
      'kakao-archive-meta': { keyPath: 'id', rows: [] },
      'identity-pins': { keyPath: 'userId', rows: [] },
      'crypto-sessions': { keyPath: 'conversationId', rows: [{ conversationId: 'c-1', sealed: 'S' }] },
      'one-time-prekeys': { keyPath: 'keyId', rows: [] },
      'content-keys': { keyPath: 'conversationId', rows: [] },
      'message-contents': { keyPath: 'key', rows: [] },
      'identity-pins-v2': { keyPath: 'id', rows: [{ id: 'u-2/d-2', userId: 'u-2', deviceId: 'd-2' }] },
      'identity-pending': { keyPath: 'userId', rows: [] },
      'history-marks': { keyPath: 'conversationId', rows: [{ conversationId: 'c-1', through: 1 }] },
    };
    const { factory, data } = versionTwoIndexedDb(v5Stores, { oldVersion: 5 });
    const idb = createIdb(factory);

    expect(await idb.all('direct-peers')).toEqual([]);
    expect(data.get('direct-peers').keyPath).toBe('conversationId');
    for (const [name, { rows }] of Object.entries(v5Stores)) expect(await idb.all(name)).toEqual(rows);
  });
});
