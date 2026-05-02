import { describe, it, expect } from 'vitest';
import {
  formatTime,
  dayKey,
  dayLabel,
  formatBytes,
} from '../lib/format.js';

describe('formatTime', () => {
  it('renders Korean noon as 오후 12', () => {
    expect(formatTime(new Date(2026, 0, 1, 12, 30), 'ko')).toBe('오후 12:30');
  });

  it('renders Korean midnight as 오전 12', () => {
    expect(formatTime(new Date(2026, 0, 1, 0, 5), 'ko')).toBe('오전 12:05');
  });

  it('renders English with 12-hour AM/PM', () => {
    expect(formatTime(new Date(2026, 0, 1, 14, 15), 'en')).toBe('2:15 PM');
  });

  it('renders Japanese with 午後/午前', () => {
    expect(formatTime(new Date(2026, 0, 1, 9, 7), 'ja')).toBe('午前 9:07');
  });

  it('falls back to Korean for unknown locale', () => {
    expect(formatTime(new Date(2026, 0, 1, 9, 7), 'xx')).toBe('오전 9:07');
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
  it('returns the today token for same-day dates', () => {
    expect(dayLabel(new Date(2026, 3, 15, 9), 'ko', today)).toBe('오늘');
    expect(dayLabel(new Date(2026, 3, 15, 9), 'en', today)).toBe('today');
    expect(dayLabel(new Date(2026, 3, 15, 9), 'ja', today)).toBe('今日');
  });

  it('returns the yesterday token for the previous day', () => {
    expect(dayLabel(new Date(2026, 3, 14, 22), 'ko', today)).toBe('어제');
    expect(dayLabel(new Date(2026, 3, 14, 22), 'en', today)).toBe('yesterday');
  });

  it('falls back to month/day in the same year', () => {
    expect(dayLabel(new Date(2026, 0, 5), 'ko', today)).toBe('1월 5일');
    expect(dayLabel(new Date(2026, 0, 5), 'en', today)).toBe('1/5');
    expect(dayLabel(new Date(2026, 0, 5), 'ja', today)).toBe('1月5日');
  });

  it('includes the year for cross-year dates', () => {
    expect(dayLabel(new Date(2024, 11, 31), 'ko', today)).toBe('2024년 12월 31일');
    expect(dayLabel(new Date(2024, 11, 31), 'en', today)).toBe('2024-12-31');
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
