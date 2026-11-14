// Muting a conversation's notifications for a while.

// How long a conversation's notifications stay off, as the mute toast
// words it.
export function muteDurationLabel(seconds) {
  if (seconds >= 86400 * 365) return '영구';
  if (seconds >= 86400) return `${Math.round(seconds / 86400)}일`;
  if (seconds >= 3600) return `${Math.round(seconds / 3600)}시간`;
  return `${Math.round(seconds / 60)}분`;
}

// Seconds from the minutes typed into the mute prompt: at least a minute,
// an hour when the input is not a number.
export const muteSecondsFromMinutes = (typed) => Math.max(1, parseInt(typed, 10) || 60) * 60;
