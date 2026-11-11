// Interim trust-on-first-use pins for peer identity keys, until wave 2 ships
// signed bundles and safety numbers. The first key the directory serves for
// a user is pinned in IndexedDB ('identity-pins': userId -> peerKey,
// firstSeenAt). A different key later never replaces the pin by itself: the
// peer is marked as changed and sending to them stays frozen until the user
// explicitly accepts the new key. Keys are fetched once per page session and
// never re-fetched because decryption failed; a server that can make
// messages fail must not be able to swap keys that way.

export function createPinStore(repo, { now = () => new Date().toISOString() } = {}) {
  return {
    async check(userId, peerKey) {
      const pin = await repo.get(userId);
      if (!pin) {
        const fresh = { userId, peerKey, firstSeenAt: now() };
        await repo.put(fresh);
        return { status: 'pinned', pin: fresh };
      }
      return { status: pin.peerKey === peerKey ? 'match' : 'changed', pin };
    },

    async accept(userId, peerKey) {
      const pin = { userId, peerKey, firstSeenAt: now() };
      await repo.put(pin);
      return pin;
    },
  };
}

export function createPeerKeyDirectory({ fetchPeerKey, pins, onKeyChange }) {
  const lookups = new Map(); // userId -> Promise<entry>
  const settled = new Map(); // userId -> { trustedKey, pendingKey }

  async function lookup(userId, handle) {
    const observed = await fetchPeerKey(userId, handle);
    const { status, pin } = await pins.check(userId, observed);
    const entry = { trustedKey: pin.peerKey, pendingKey: status === 'changed' ? observed : null };
    settled.set(userId, entry);
    if (entry.pendingKey) onKeyChange?.(userId);
    return entry;
  }

  return {
    resolve(userId, handle) {
      if (!lookups.has(userId)) {
        const pending = lookup(userId, handle);
        lookups.set(userId, pending);
        // Only an unreachable directory is retried; a resolved key is final
        // for this page session.
        pending.catch(() => lookups.delete(userId));
      }
      return lookups.get(userId);
    },

    pendingChange(userId) {
      return settled.get(userId)?.pendingKey ?? null;
    },

    async accept(userId) {
      const entry = settled.get(userId);
      if (!entry?.pendingKey) return false;
      await pins.accept(userId, entry.pendingKey);
      const accepted = { trustedKey: entry.pendingKey, pendingKey: null };
      settled.set(userId, accepted);
      lookups.set(userId, Promise.resolve(accepted));
      return true;
    },

    reset() {
      lookups.clear();
      settled.clear();
    },
  };
}
