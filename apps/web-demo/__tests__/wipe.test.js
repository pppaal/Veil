import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import { IDB_NAME } from '../src/platform/idb.js';
import { wipeEverything } from '../src/platform/wipe.js';

function memoryStorage(entries) {
  const map = new Map(Object.entries(entries));
  return {
    get length() { return map.size; },
    key: (i) => [...map.keys()][i] ?? null,
    removeItem: (key) => { map.delete(key); },
    keys: () => [...map.keys()].sort(),
  };
}

// indexedDB double whose delete request settles the way the test asks.
function fakeIndexedDB(outcome = 'success') {
  return {
    deleteDatabase: vi.fn(() => {
      const request = {};
      queueMicrotask(() => {
        if (outcome === 'error') {
          request.error = new Error('delete failed');
          request.onerror();
        } else if (outcome === 'blocked') {
          request.onblocked();
        } else {
          request.onsuccess();
        }
      });
      return request;
    }),
  };
}

function fakeCaches(names) {
  const remaining = new Set(names);
  return {
    keys: vi.fn(async () => [...remaining]),
    delete: vi.fn(async (name) => remaining.delete(name)),
    remaining,
  };
}

describe('wipeEverything', () => {
  it('deletes the database, every veil- key and Cache Storage', async () => {
    const order = [];
    const closeDatabase = vi.fn(async () => { order.push('close'); });
    const indexedDB = fakeIndexedDB();
    indexedDB.deleteDatabase.mockImplementationOnce((name) => {
      order.push(`delete:${name}`);
      const request = {};
      queueMicrotask(() => request.onsuccess());
      return request;
    });
    const localStorage = memoryStorage({
      'veil-demo-session': '{"legacy":true}',
      'veil-demo-muted-convs-v1': '["c-1"]',
      'veil-demo-theme': 'light',
      'veil-demo-notification-level-v1': 'sender',
      'other-app': 'keep',
    });
    const sessionStorage = memoryStorage({ 'veil-demo-tab': '1', unrelated: 'keep' });
    const caches = fakeCaches(['veil-shell-v1', 'veil-assets']);

    await wipeEverything({ closeDatabase, indexedDB, localStorage, sessionStorage, caches });

    expect(order).toEqual(['close', `delete:${IDB_NAME}`]);
    expect(IDB_NAME).toBe('veil-demo');
    expect(localStorage.keys()).toEqual(['other-app']);
    expect(sessionStorage.keys()).toEqual(['unrelated']);
    expect(caches.remaining.size).toBe(0);
  });

  it('covers Kakao archives and pins by deleting the whole database, not individual stores', async () => {
    const indexedDB = fakeIndexedDB();
    await wipeEverything({ indexedDB, localStorage: memoryStorage({}), sessionStorage: memoryStorage({}) });
    expect(indexedDB.deleteDatabase).toHaveBeenCalledTimes(1);
    expect(indexedDB.deleteDatabase).toHaveBeenCalledWith('veil-demo');
  });

  it('finishes the other steps and then reports a failed delete', async () => {
    const localStorage = memoryStorage({ 'veil-demo-theme': 'dark' });
    const caches = fakeCaches(['veil-shell-v1']);
    await expect(wipeEverything({ indexedDB: fakeIndexedDB('error'), localStorage, sessionStorage: null, caches }))
      .rejects.toBeInstanceOf(AggregateError);
    expect(localStorage.keys()).toEqual([]);
    expect(caches.remaining.size).toBe(0);
  });

  describe('a blocked delete', () => {
    beforeEach(() => { vi.useFakeTimers(); });
    afterEach(() => { vi.useRealTimers(); });

    it('is waited out and reported, while the other steps go ahead', async () => {
      const indexedDB = fakeIndexedDB('blocked');
      const onBlocked = vi.fn();
      const localStorage = memoryStorage({ 'veil-demo-theme': 'dark' });
      let finished = false;
      const wipe = wipeEverything({ indexedDB, localStorage, sessionStorage: null, onBlocked })
        .then(() => { finished = true; });

      await vi.advanceTimersByTimeAsync(5000);
      expect(onBlocked).toHaveBeenCalledTimes(1);
      expect(localStorage.keys()).toEqual([]);
      // The database and the keys in it are still there: not a finished wipe.
      expect(finished).toBe(false);

      // The other tab closes and the queued delete goes through.
      indexedDB.deleteDatabase.mock.results[0].value.onsuccess();
      await wipe;
      expect(finished).toBe(true);
    });

    it('is not reported when it clears at once, as when this tab finishes a last write', async () => {
      const indexedDB = fakeIndexedDB('blocked');
      const onBlocked = vi.fn();
      const wipe = wipeEverything({ indexedDB, localStorage: null, sessionStorage: null, onBlocked });

      await vi.advanceTimersByTimeAsync(50);
      indexedDB.deleteDatabase.mock.results[0].value.onsuccess();
      await wipe;
      await vi.advanceTimersByTimeAsync(5000);
      expect(onBlocked).not.toHaveBeenCalled();
    });
  });
});
