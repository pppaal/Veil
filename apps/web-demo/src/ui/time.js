// Times and days as the UI shows them (lib/format.js renders them).

import { dayKey, dayLabel as formatDayLabel, formatTime } from '../../lib/format.js';

export { dayKey };

export const timeOfDay = (date) => formatTime(date);
export const dayLabel = (date) => formatDayLabel(date);

// A conversation row's time: the time of day for today, else the day.
export function relativeTime(iso) {
  const date = new Date(iso);
  const now = new Date();
  if (date.toDateString() === now.toDateString()) return formatTime(date);
  return formatDayLabel(date, now);
}
