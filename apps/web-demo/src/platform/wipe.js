// Removes everything the web client stored in this browser: the IndexedDB
// database (identity keys, pins, caches, queue, Kakao archives), every
// 'veil-' localStorage and sessionStorage key (muted conversations and
// preferences included) and Cache Storage. Each step runs even if an
// earlier one failed; failures are reported together at the end because a
// half-finished wipe must not look like a finished one.

import { IDB_NAME } from './idb.js';

const STORAGE_PREFIX = 'veil-';

export async function wipeEverything({
  closeDatabase,
  indexedDB,
  localStorage,
  sessionStorage,
  caches,
  databaseName = IDB_NAME,
}) {
  const failures = [];
  const attempt = async (step) => {
    try {
      await step();
    } catch (error) {
      failures.push(error);
    }
  };
  await attempt(async () => closeDatabase?.());
  await attempt(() => deleteDatabase(indexedDB, databaseName));
  await attempt(() => removePrefixedKeys(localStorage));
  await attempt(() => removePrefixedKeys(sessionStorage));
  await attempt(async () => {
    if (!caches) return;
    for (const name of await caches.keys()) await caches.delete(name);
  });
  if (failures.length > 0) throw new AggregateError(failures, 'wipe incomplete');
}

function deleteDatabase(factory, name) {
  return new Promise((resolve, reject) => {
    const request = factory.deleteDatabase(name);
    request.onsuccess = () => resolve();
    request.onerror = () => reject(request.error);
    // Another tab still has it open; the delete completes once that tab
    // closes its connection (the app closes on versionchange).
    request.onblocked = () => resolve();
  });
}

function removePrefixedKeys(storage) {
  if (!storage) return;
  const keys = [];
  for (let i = 0; i < storage.length; i += 1) keys.push(storage.key(i));
  for (const key of keys) {
    if (key?.startsWith(STORAGE_PREFIX)) storage.removeItem(key);
  }
}
