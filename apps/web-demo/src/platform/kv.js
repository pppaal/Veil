// The key-value interface the crypto stores are written against, with an
// IndexedDB implementation for the app and an in-memory one for tests:
//   get(key) -> row | null, put(row), delete(key),
//   byIndex(value) -> rows whose indexed field equals value,
//   dueBy(time) -> rows whose expiry field is set and at most time.

export function createIdbKv(idb, storeName, { index = null, expiryIndex = null } = {}) {
  return {
    get: (key) => idb.get(storeName, key),
    put: (row) => idb.put(storeName, row),
    delete: (key) => idb.delete(storeName, key),
    byIndex: (value) => idb.allByIndex(storeName, index, value),
    // IndexedDB leaves a row whose expiry is null out of the index.
    dueBy: (time) => idb.allByIndexUpTo(storeName, expiryIndex, time),
  };
}

// Copies on the way in and out, as IndexedDB's structured clone does, so no
// caller ever shares an object with what is stored. all() lets tests look at
// everything a store holds.
export function createMemoryKv(keyPath, { indexField = null, expiryField = null } = {}) {
  const rows = new Map();
  const all = () => [...rows.values()].map((row) => structuredClone(row));
  return {
    rows,
    get: async (key) => (rows.has(key) ? structuredClone(rows.get(key)) : null),
    put: async (row) => { rows.set(row[keyPath], structuredClone(row)); },
    delete: async (key) => { rows.delete(key); },
    all: async () => all(),
    byIndex: async (value) => all().filter((row) => row[indexField] === value),
    dueBy: async (time) => all().filter((row) => Number.isFinite(row[expiryField]) && row[expiryField] <= time),
  };
}
