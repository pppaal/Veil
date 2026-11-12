// Times and days as the UI shows them, in the active language
// (lib/format.js renders the tokens: 오늘 / today / 今日, 오전 / AM / 午前).

import { activeLang } from '../../i18n/i18n.js';
import { dayKey, dayLabel as formatDayLabel, formatTime } from '../../lib/format.js';

export { dayKey };

export const timeOfDay = (date) => formatTime(date, activeLang());
export const dayLabel = (date) => formatDayLabel(date, activeLang());

// A conversation row's time: the time of day for today, else the day.
export function relativeTime(iso) {
  const date = new Date(iso);
  const now = new Date();
  if (date.toDateString() === now.toDateString()) return formatTime(date, activeLang());
  return formatDayLabel(date, activeLang(), now);
}
