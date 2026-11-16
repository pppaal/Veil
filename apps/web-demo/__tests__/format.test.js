import { describe, it, expect } from 'vitest';
import {
  formatTime,
  dayKey,
  dayLabel,
  listDate,
  calendarDaysBetween,
  formatBytes,
} from '../lib/format.js';
import { relativeTime } from '../src/ui/time.js';

describe('formatTime', () => {
  it('renders 12-hour time with AM/PM', () => {
    expect(formatTime(new Date(2026, 0, 1, 14, 15))).toBe('2:15 PM');
    expect(formatTime(new Date(2026, 0, 1, 9, 7))).toBe('9:07 AM');
  });

  it('renders noon as 12 PM', () => {
    expect(formatTime(new Date(2026, 0, 1, 12, 30))).toBe('12:30 PM');
  });

  it('renders midnight as 12 AM', () => {
    expect(formatTime(new Date(2026, 0, 1, 0, 5))).toBe('12:05 AM');
  });

  it('takes an ISO string as well as a Date', () => {
    expect(formatTime(new Date(2026, 0, 1, 9, 7).toISOString())).toBe('9:07 AM');
  });
});

describe('dayKey', () => {
  it('matches the current calendar day even at midnight UTC offsets', () => {
    expect(dayKey(new Date(2026, 3, 15))).toBe('2026-4-15');
    expect(dayKey(new Date(2026, 3, 15, 23, 59))).toBe('2026-4-15');
  });
});

describe('dayLabel', () => {
  const today = new Date(2026, 3, 15, 12);
  it('returns Today for same-day dates', () => {
    expect(dayLabel(new Date(2026, 3, 15, 9), today)).toBe('Today');
  });

  it('returns Yesterday for the previous day', () => {
    expect(dayLabel(new Date(2026, 3, 14, 22), today)).toBe('Yesterday');
  });

  // The divider in a chat names the same day its row in Chats does ("Mon"),
  // in full, as the phone's divider does.
  it('names the weekday for the six days before yesterday', () => {
    expect(dayLabel(new Date(2026, 3, 13, 9), today)).toBe('Monday');
    expect(dayLabel(new Date(2026, 3, 9, 9), today)).toBe('Thursday');
    expect(dayLabel(new Date(2026, 3, 8, 9), today)).toBe('Apr 8');
  });

  it('calls a message stamped ahead of this clock today, as its Chats row shows its time', () => {
    expect(dayLabel(new Date(2026, 3, 16, 0, 5), today)).toBe('Today');
  });

  it('falls back to the month and day in the same year', () => {
    expect(dayLabel(new Date(2026, 0, 5), today)).toBe('Jan 5');
  });

  it('includes the year for cross-year dates', () => {
    expect(dayLabel(new Date(2024, 11, 31), today)).toBe('Dec 31, 2024');
  });
});

// A chat's row in Chats, as the phone's Chats row writes it
// (apps/mobile/test/chat/message_time_test.dart, the same cases).
describe('listDate', () => {
  // Tuesday, April 7, 2026, 10:20 in the morning.
  const now = new Date(2026, 3, 7, 10, 20);
  const row = (date) => listDate(date, now);

  it('shows the time for a message sent today', () => {
    expect(row(new Date(2026, 3, 7, 9, 45))).toBe('9:45 AM');
    expect(row(new Date(2026, 3, 7, 0, 1))).toBe('12:01 AM');
  });

  it('says "Yesterday" for the day before, whatever the hour', () => {
    expect(row(new Date(2026, 3, 6, 23, 59))).toBe('Yesterday');
    expect(row(new Date(2026, 3, 6, 0, 1))).toBe('Yesterday');
  });

  it('shows the short weekday for the six days before that', () => {
    expect(row(new Date(2026, 3, 5, 12))).toBe('Sun');
    expect(row(new Date(2026, 3, 4, 18, 40))).toBe('Sat');
    expect(row(new Date(2026, 3, 1, 8))).toBe('Wed');
  });

  it('shows the short date from a week back', () => {
    // Seven days ago, the same weekday as today.
    expect(row(new Date(2026, 2, 31, 23, 59))).toBe('Mar 31');
    expect(row(new Date(2026, 0, 2, 9))).toBe('Jan 2');
  });

  it('adds the year to a date in another year', () => {
    expect(row(new Date(2025, 11, 31, 9))).toBe('Dec 31, 2025');
    expect(row(new Date(2025, 3, 7, 9))).toBe('Apr 7, 2025');
  });

  // A browser whose clock is behind the server's sees a message from
  // "later": it is shown by its time, not as a day.
  it('shows the time for a message stamped after now', () => {
    expect(row(new Date(2026, 3, 7, 10, 25))).toBe('10:25 AM');
    expect(row(new Date(2026, 3, 8, 0, 5))).toBe('12:05 AM');
  });

  it('counts calendar days across a clock change', () => {
    expect(calendarDaysBetween(new Date(2026, 2, 28, 23), new Date(2026, 2, 29, 1))).toBe(1);
    expect(calendarDaysBetween(new Date(2026, 2, 25, 12), new Date(2026, 3, 1, 12))).toBe(7);
    expect(calendarDaysBetween(new Date(2026, 9, 24, 12), new Date(2026, 9, 26, 0, 30))).toBe(2);
  });

  it("is what a conversation row shows for the server's timestamp", () => {
    expect(relativeTime(new Date(2026, 3, 4, 18, 40).toISOString(), now)).toBe('Sat');
    expect(relativeTime(new Date(2026, 3, 6, 20, 15).toISOString(), now)).toBe('Yesterday');
    expect(relativeTime(new Date(2026, 3, 7, 9, 45).toISOString(), now)).toBe('9:45 AM');
  });
});

describe('formatBytes', () => {
  it('renders B / KB / MB / GB at boundaries', () => {
    expect(formatBytes(0)).toBe('0 B');
    expect(formatBytes(512)).toBe('512 B');
    expect(formatBytes(1024)).toBe('1.0 KB');
    expect(formatBytes(1024 * 1024)).toBe('1.0 MB');
    expect(formatBytes(1024 * 1024 * 1024)).toBe('1.00 GB');
  });

  it('returns an empty string for an unknown size', () => {
    expect(formatBytes(NaN)).toBe('');
    expect(formatBytes(-1)).toBe('');
    expect(formatBytes('not a number')).toBe('');
  });
});
