// An in-memory stand-in for the IndexedDB row app.js keeps the session
// record in (src/platform/session-store.js). As in the IndexedDB transaction
// behind the real one, modify reads and writes with nothing able to land in
// between. With clone, records are copied on the way in and out as
// structured clone does, so every session store over the repo holds its own
// copy of the record, as every browser tab does.

import { vi } from 'vitest';

export function memorySessionRepo(initial = null, { clone = false } = {}) {
  const copy = clone ? (record) => structuredClone(record) : (record) => record;
  let value = copy(initial);
  return {
    get: vi.fn(async () => copy(value)),
    put: vi.fn(async (next) => { value = copy(next); }),
    modify: vi.fn(async (transform) => {
      const next = transform(copy(value));
      if (next !== null) value = copy(next);
      return copy(next);
    }),
    peek: () => value,
  };
}
