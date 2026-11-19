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

// The day a message is filed under in a chat: its own, or today for one
// stamped later than this clock reads, which dayLabel calls "Today", so
// that it shares today's divider and does not get a second "Today".
export function dayKey(date, today = new Date()) {
  const at = date instanceof Date ? date : new Date(date);
  const d = calendarDaysBetween(at, today) < 0 ? today : at;
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

// Bytes as WhatsApp and Signal write them, and as the phone does: whole
// bytes and kilobytes ("56 KB"), megabytes and gigabytes to one place without
// a trailing ".0" ("2.3 MB", "5 GB"). A size is rounded first and moves up a
// unit when the rounded number reaches 1024. An empty string for an unknown
// size.
export function formatBytes(n) {
  if (typeof n !== 'number' || !Number.isFinite(n) || n < 0) return '';
  if (n < 1024) return `${n} B`;
  const kb = Math.round(n / 1024);
  if (kb < 1024) return `${kb} KB`;
  const onePlace = (value) => value.toFixed(1).replace(/\.0$/, '');
  const mb = Number((n / 1024 / 1024).toFixed(1));
  if (mb < 1024) return `${onePlace(mb)} MB`;
  return `${onePlace(n / 1024 / 1024 / 1024)} GB`;
}
