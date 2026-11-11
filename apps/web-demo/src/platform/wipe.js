// Removes everything the web client stored in this browser: the IndexedDB
// database (identity keys, pins, caches, queue, Kakao archives), every
// 'veil-' localStorage and sessionStorage key (muted conversations and
// preferences included) and Cache Storage. Each step runs even if an
// earlier one failed; failures are reported together at the end because a
// half-finished wipe must not look like a finished one.

import { IDB_NAME } from './idb.js';

const STORAGE_PREFIX = 'veil-';
const BLOCKED_REPORT_DELAY_MS = 1000;

// onBlocked fires when a connection that does not let go of the database (a
// tab on a build from before tabs closed it for a wipe) holds up the delete.
// The wipe then waits for that tab to close instead of reporting a finished
// wipe while the database and its keys are still there.
export async function wipeEverything({
  closeDatabase,
  indexedDB,
  localStorage,
  sessionStorage,
  caches,
  onBlocked,
  databaseName = IDB_NAME,
}) {
  const { attempt, finish } = collectFailures();
  await attempt(async () => closeDatabase?.());
  // Started first and awaited last, so a blocked delete does not hold up the
  // other steps.
  const databaseDeleted = attempt(() => deleteDatabase(indexedDB, databaseName, onBlocked));
  await clearBrowserStorage(attempt, { localStorage, sessionStorage, caches });
  await databaseDeleted;
  finish();
}

// The same wipe without deleting the database, for an identity replaced in
// place: clearDatabase empties it but for the record that replaced the old
// one, which the caller has already written.
export async function wipeInPlace({ clearDatabase, localStorage, sessionStorage, caches }) {
  const { attempt, finish } = collectFailures();
  await attempt(clearDatabase);
  await clearBrowserStorage(attempt, { localStorage, sessionStorage, caches });
  finish();
}

function collectFailures() {
  const failures = [];
  return {
    async attempt(step) {
      try {
        await step();
      } catch (error) {
        failures.push(error);
      }
    },
    finish() {
      if (failures.length > 0) throw new AggregateError(failures, 'wipe incomplete');
    },
  };
}

async function clearBrowserStorage(attempt, { localStorage, sessionStorage, caches }) {
  await attempt(() => removePrefixedKeys(localStorage));
  await attempt(() => removePrefixedKeys(sessionStorage));
  await attempt(async () => {
    if (!caches) return;
    for (const name of await caches.keys()) await caches.delete(name);
  });
}

function deleteDatabase(factory, name, onBlocked) {
  return new Promise((resolve, reject) => {
    let report = null;
    const settle = (finish) => () => {
      clearTimeout(report);
      finish();
    };
    const request = factory.deleteDatabase(name);
    request.onsuccess = settle(resolve);
    request.onerror = settle(() => reject(request.error));
    // The request stays queued and succeeds once the connection holding it up
    // closes. This tab's own closing connection can hold it up for a moment
    // while a last transaction commits, so only a block that lasts is reported.
    request.onblocked = () => {
      report = setTimeout(() => onBlocked?.(), BLOCKED_REPORT_DELAY_MS);
    };
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
