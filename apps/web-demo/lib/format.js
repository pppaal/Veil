// Pure format helpers extracted from app.js for unit-testable parity. Times
// and days are rendered in English, the app's only language.

const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

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

// A day as the dividers show it: "Today", "Yesterday", "Jan 5" within the
// year, else "Dec 31, 2024".
export function dayLabel(date, today = new Date()) {
  const d = date instanceof Date ? date : new Date(date);
  if (dayKey(d) === dayKey(today)) return 'Today';
  const yesterday = new Date(today);
  yesterday.setDate(yesterday.getDate() - 1);
  if (dayKey(d) === dayKey(yesterday)) return 'Yesterday';
  const monthDay = `${MONTHS[d.getMonth()]} ${d.getDate()}`;
  if (d.getFullYear() === today.getFullYear()) return monthDay;
  return `${monthDay}, ${d.getFullYear()}`;
}

// Bytes → human-readable.
export function formatBytes(n) {
  if (typeof n !== 'number' || !Number.isFinite(n) || n < 0) return '—';
  if (n < 1024) return `${n} B`;
  if (n < 1024 * 1024) return `${(n / 1024).toFixed(1)} KB`;
  if (n < 1024 * 1024 * 1024) return `${(n / 1024 / 1024).toFixed(1)} MB`;
  return `${(n / 1024 / 1024 / 1024).toFixed(2)} GB`;
}
