import { describe, it, expect } from 'vitest';
import {
  formatTime,
  dayKey,
  dayLabel,
  formatBytes,
} from '../lib/format.js';

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

  it('falls back to the month and day in the same year', () => {
    expect(dayLabel(new Date(2026, 0, 5), today)).toBe('Jan 5');
  });

  it('includes the year for cross-year dates', () => {
    expect(dayLabel(new Date(2024, 11, 31), today)).toBe('Dec 31, 2024');
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

  it('returns em-dash on invalid input', () => {
    expect(formatBytes(NaN)).toBe('—');
    expect(formatBytes(-1)).toBe('—');
    expect(formatBytes('not a number')).toBe('—');
  });
});
