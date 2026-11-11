// The key-value interface the crypto stores are written against, with an
// IndexedDB implementation for the app and an in-memory one for tests:
//   get(key) -> row | null, put(row), delete(key), all() -> rows,
//   byIndex(value) -> rows whose indexed field equals value.

export function createIdbKv(idb, storeName, { index = null } = {}) {
  return {
    get: (key) => idb.get(storeName, key),
    put: (row) => idb.put(storeName, row),
    delete: (key) => idb.delete(storeName, key),
    all: () => idb.all(storeName),
    byIndex: (value) => idb.allByIndex(storeName, index, value),
  };
}

// Copies on the way in and out, as IndexedDB's structured clone does, so no
// caller ever shares an object with what is stored.
export function createMemoryKv(keyPath, { indexField = null } = {}) {
  const rows = new Map();
  const all = () => [...rows.values()].map((row) => structuredClone(row));
  return {
    rows,
    get: async (key) => (rows.has(key) ? structuredClone(rows.get(key)) : null),
    put: async (row) => { rows.set(row[keyPath], structuredClone(row)); },
    delete: async (key) => { rows.delete(key); },
    all: async () => all(),
    byIndex: async (value) => all().filter((row) => row[indexField] === value),
  };
}
