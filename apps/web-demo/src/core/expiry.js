// Contract C4: a message expires at the earlier of the expiry inside its
// authenticated payload and the one the relay set on the envelope. The relay
// may bring an expiry forward but never push it back, and once it has passed
// nothing of the message stays on this device (src/domain/ingest.js,
// src/platform/content-store.js).

// The earlier of two expiries in ms; either may be null.
export function earlierExpiry(a, b) {
  if (!Number.isFinite(a)) return Number.isFinite(b) ? b : null;
  return Number.isFinite(b) ? Math.min(a, b) : a;
}

// innerMs: the authenticated expiry (ms) or null; relayedIso: the
// envelope's expiresAt (ISO-8601) or null.
export function effectiveExpiry(innerMs, relayedIso) {
  return earlierExpiry(innerMs, relayedIso ? Date.parse(relayedIso) : null);
}

export const isPast = (expiresAtMs, now) => Number.isFinite(expiresAtMs) && expiresAtMs <= now;
