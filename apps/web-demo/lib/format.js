// Pure format helpers extracted from app.js for unit-testable parity.
// Korean defaults are intentional; en/ja overrides come via the
// optional locale arg.

const KO = {
  today: '오늘',
  yesterday: '어제',
  am: '오전',
  pm: '오후',
  monthDay: (m, d) => `${m}월 ${d}일`,
  yearMonthDay: (y, m, d) => `${y}년 ${m}월 ${d}일`,
};
const EN = {
  today: 'today',
  yesterday: 'yesterday',
  am: 'AM',
  pm: 'PM',
  monthDay: (m, d) => `${m}/${d}`,
  yearMonthDay: (y, m, d) => `${y}-${m}-${d}`,
};
const JA = {
  today: '今日',
  yesterday: '昨日',
  am: '午前',
  pm: '午後',
  monthDay: (m, d) => `${m}月${d}日`,
  yearMonthDay: (y, m, d) => `${y}年${m}月${d}日`,
};
const PACK = { ko: KO, en: EN, ja: JA };

function pack(locale) {
  return PACK[locale] ?? KO;
}

export function formatTime(date, locale = 'ko') {
  const d = date instanceof Date ? date : new Date(date);
  const p = pack(locale);
  const h = d.getHours();
  const m = d.getMinutes();
  if (locale === 'en') {
    const ampm = h < 12 ? 'AM' : 'PM';
    const h12 = h % 12 === 0 ? 12 : h % 12;
    return `${h12}:${String(m).padStart(2, '0')} ${ampm}`;
  }
  const ampm = h < 12 ? p.am : p.pm;
  const h12 = h % 12 === 0 ? 12 : h % 12;
  return `${ampm} ${h12}:${String(m).padStart(2, '0')}`;
}

export function dayKey(date) {
  const d = date instanceof Date ? date : new Date(date);
  return `${d.getFullYear()}-${d.getMonth() + 1}-${d.getDate()}`;
}

export function dayLabel(date, locale = 'ko', today = new Date()) {
  const d = date instanceof Date ? date : new Date(date);
  const p = pack(locale);
  if (dayKey(d) === dayKey(today)) return p.today;
  const yesterday = new Date(today);
  yesterday.setDate(yesterday.getDate() - 1);
  if (dayKey(d) === dayKey(yesterday)) return p.yesterday;
  if (d.getFullYear() === today.getFullYear()) {
    return p.monthDay(d.getMonth() + 1, d.getDate());
  }
  return p.yearMonthDay(d.getFullYear(), d.getMonth() + 1, d.getDate());
}

// Bytes → human-readable. Same defaults across locales.
export function formatBytes(n) {
  if (typeof n !== 'number' || !Number.isFinite(n) || n < 0) return '—';
  if (n < 1024) return `${n} B`;
  if (n < 1024 * 1024) return `${(n / 1024).toFixed(1)} KB`;
  if (n < 1024 * 1024 * 1024) return `${(n / 1024 / 1024).toFixed(1)} MB`;
  return `${(n / 1024 / 1024 / 1024).toFixed(2)} GB`;
}
