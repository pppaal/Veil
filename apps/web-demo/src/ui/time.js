// Times and days as the UI shows them (lib/format.js renders them).

import { dayKey, dayLabel as formatDayLabel, formatTime, listDate } from '../../lib/format.js';

export { dayKey };

export const timeOfDay = (date) => formatTime(date);
export const dayLabel = (date) => formatDayLabel(date);

// A conversation row's time: the time of day for today, "Yesterday", the
// short weekday for the six days before, then the day (lib/format.js
// listDate).
export const relativeTime = (iso, now = new Date()) => listDate(new Date(iso), now);
