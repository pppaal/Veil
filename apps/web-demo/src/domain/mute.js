// Muting a conversation's notifications for a while.

const count = (n, unit) => `for ${n} ${n === 1 ? unit : `${unit}s`}`;

// How long a conversation's notifications stay off, as the mute toast words
// it: "for 10 minutes", "for 2 hours", "for 3 days" or "for good".
export function muteDurationLabel(seconds) {
  if (seconds >= 86400 * 365) return 'for good';
  if (seconds >= 86400) return count(Math.round(seconds / 86400), 'day');
  if (seconds >= 3600) return count(Math.round(seconds / 3600), 'hour');
  return count(Math.round(seconds / 60), 'minute');
}

// Seconds from the minutes typed into the mute prompt: at least a minute,
// an hour when the input is not a number.
export const muteSecondsFromMinutes = (typed) => Math.max(1, parseInt(typed, 10) || 60) * 60;
