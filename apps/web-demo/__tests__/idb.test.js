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
