// Muting a conversation's notifications for a while, or for good.

const count = (n, unit) => `${n} ${n === 1 ? unit : `${unit}s`}`;

const WEEK = 7 * 86400;

// How long a timed mute lasts, as the mute toast words it after "Muted for":
// "1 hour", "8 hours", "1 week".
export function muteDurationLabel(seconds) {
  if (seconds >= WEEK && seconds % WEEK === 0) return count(seconds / WEEK, 'week');
  if (seconds >= 86400) return count(Math.round(seconds / 86400), 'day');
  if (seconds >= 3600) return count(Math.round(seconds / 3600), 'hour');
  return count(Math.max(1, Math.round(seconds / 60)), 'minute');
}

// The muted conversations as convId -> the time the mute ends (ms), or null
// for one with no end. Ids alone (the form earlier builds stored) are mutes
// with no end; mutes that have ended are dropped.
export function muteEntries(stored, nowMs) {
  const mutes = new Map();
  if (!Array.isArray(stored)) return mutes;
  for (const entry of stored) {
    if (typeof entry === 'string') mutes.set(entry, null);
    else if (Array.isArray(entry) && typeof entry[0] === 'string' && Number.isFinite(entry[1]) && entry[1] > nowMs) mutes.set(entry[0], entry[1]);
  }
  return mutes;
}

// The stored form of muteEntries: an id for a mute with no end, [id, endMs]
// for a timed one. A set of ids is a set of mutes with no end.
export function storedMutes(mutes) {
  const entries = mutes instanceof Map ? [...mutes] : [...mutes].map((id) => [id, null]);
  return entries.map(([id, until]) => (until == null ? id : [id, until]));
}

// Whether a mute (an entry of muteEntries) still holds at nowMs.
export const isMutedAt = (mutes, convId, nowMs) => mutes.has(convId) && (mutes.get(convId) == null || mutes.get(convId) > nowMs);
