// Pure format helpers extracted from app.js for unit-testable parity. Times
// and days are rendered in English, the app's only language.

const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const MONTH_NAMES = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];
const WEEKDAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
const WEEKDAY_NAMES = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];

// A time of day as "2:15 PM".
export function formatTime(date) {
  const d = date instanceof Date ? date : new Date(date);
  const h = d.getHours();
  const m = d.getMinutes();
  const ampm = h < 12 ? 'AM' : 'PM';
  const h12 = h % 12 === 0 ? 12 : h % 12;
  return `${h12}:${String(m).padStart(2, '0')} ${ampm}`;
}

export function dayKey(date) {
  const d = date instanceof Date ? date : new Date(date);
  return `${d.getFullYear()}-${d.getMonth() + 1}-${d.getDate()}`;
}

// A day as the dividers show it, as the phone's do (apps/mobile
// chat_message_runs.dart chatDayLabel): "Today" (also for a message stamped
// later than this clock reads, which the Chats row shows by its time),
// "Yesterday", the weekday for the six days before ("Monday"), "January 5"
// within the year, else "December 31, 2024".
export function dayLabel(date, today = new Date()) {
  const d = date instanceof Date ? date : new Date(date);
  const daysAgo = calendarDaysBetween(d, today);
  if (daysAgo <= 0) return 'Today';
  if (daysAgo === 1) return 'Yesterday';
  if (daysAgo < 7) return WEEKDAY_NAMES[d.getDay()];
  return monthDay(d, today, MONTH_NAMES);
}

// "Jan 5" (with `names` the full month names, "January 5") when `d` is in
// the year of `today`, else with the year: "Dec 31, 2024".
function monthDay(d, today, names = MONTHS) {
  const day = `${names[d.getMonth()]} ${d.getDate()}`;
  return d.getFullYear() === today.getFullYear() ? day : `${day}, ${d.getFullYear()}`;
}

// How many calendar days `later` is after `earlier`, each on the day it
// falls on locally: 0 on the same day, 1 for the day before, whatever the
// hours (a day with a clock change is 23 or 25 hours long).
export function calendarDaysBetween(earlier, later) {
  const from = Date.UTC(earlier.getFullYear(), earlier.getMonth(), earlier.getDate());
  const to = Date.UTC(later.getFullYear(), later.getMonth(), later.getDate());
  return Math.round((to - from) / 86_400_000);
}

// When a chat's last message was sent, as its row in Chats shows it (the
// phone's Chats row too: apps/mobile message_time.dart listDate): the time
// for today, "Yesterday", the short weekday ("Sat") for the six days
// before, then the short date ("Mar 30", "Dec 31, 2024").
export function listDate(date, now = new Date()) {
  const d = date instanceof Date ? date : new Date(date);
  const daysAgo = calendarDaysBetween(d, now);
  if (daysAgo <= 0) return formatTime(d);
  if (daysAgo === 1) return 'Yesterday';
  if (daysAgo < 7) return WEEKDAYS[d.getDay()];
  return monthDay(d, now);
}

// Bytes as a human-readable size; an empty string for an unknown one.
export function formatBytes(n) {
  if (typeof n !== 'number' || !Number.isFinite(n) || n < 0) return '';
  if (n < 1024) return `${n} B`;
  if (n < 1024 * 1024) return `${(n / 1024).toFixed(1)} KB`;
  if (n < 1024 * 1024 * 1024) return `${(n / 1024 / 1024).toFixed(1)} MB`;
  return `${(n / 1024 / 1024 / 1024).toFixed(2)} GB`;
}
