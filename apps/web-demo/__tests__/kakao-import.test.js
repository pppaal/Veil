import { describe, it, expect } from 'vitest';
import { parseKakaoExport } from '../lib/kakao-import.js';

describe('parseKakaoExport — Android format', () => {
  it('parses a basic two-message conversation', () => {
    const txt = [
      '[홍길동] [2024. 3. 15. 오후 2:34] 안녕하세요',
      '[김철수] [2024. 3. 15. 오후 2:35] 네 반갑습니다',
    ].join('\n');
    const out = parseKakaoExport(txt);
    expect(out.participants.sort()).toEqual(['김철수', '홍길동']);
    expect(out.messages).toHaveLength(2);
    expect(out.messages[0].kind).toBe('msg');
    expect(out.messages[0].sender).toBe('홍길동');
    expect(out.messages[0].body).toBe('안녕하세요');
  });

  it('handles 오전 12 (midnight) and 오후 12 (noon) correctly', () => {
    const txt = [
      '[A] [2024. 3. 15. 오전 12:05] midnight',
      '[A] [2024. 3. 15. 오후 12:05] noon',
    ].join('\n');
    const out = parseKakaoExport(txt);
    const t0 = new Date(out.messages[0].sentAt);
    const t1 = new Date(out.messages[1].sentAt);
    expect(t0.getHours()).toBe(0);
    expect(t1.getHours()).toBe(12);
  });

  it('appends continuation lines to the previous message body', () => {
    const txt = [
      '[홍길동] [2024. 3. 15. 오후 2:34] line one',
      'line two',
      'line three',
    ].join('\n');
    const out = parseKakaoExport(txt);
    expect(out.messages).toHaveLength(1);
    expect(out.messages[0].body).toBe('line one\nline two\nline three');
  });

  it('preserves date divider context in pendingDate', () => {
    const txt = [
      '--------------- 2024년 3월 16일 토요일 ---------------',
      '[A] [2024. 3. 16. 오전 10:00] 토요일이네요',
    ].join('\n');
    const out = parseKakaoExport(txt);
    expect(out.pendingDate).toBe('2024-3-16');
  });
});

describe('parseKakaoExport — iOS / macOS format', () => {
  it('parses the comma-separated shape', () => {
    const txt = [
      '2024. 3. 15. 오후 2:34, 홍길동 : 안녕하세요',
      '2024. 3. 15. 오후 2:35, 김철수 : 네',
    ].join('\n');
    const out = parseKakaoExport(txt);
    expect(out.participants.sort()).toEqual(['김철수', '홍길동']);
    expect(out.messages[0].body).toBe('안녕하세요');
  });
});

describe('parseKakaoExport — robustness', () => {
  it('handles empty input', () => {
    expect(parseKakaoExport('')).toEqual({
      participants: [], messages: [], errors: ['empty input'],
    });
  });

  it('records header lines as system kind without crashing', () => {
    const txt = [
      'KakaoTalk 대화 — 저장된 날짜: 2024-03-15',
      '[A] [2024. 3. 15. 오후 2:34] hi',
    ].join('\n');
    const out = parseKakaoExport(txt);
    expect(out.messages[0].kind).toBe('system');
    expect(out.messages[1].kind).toBe('msg');
  });

  it('reports unparseable timestamps without aborting', () => {
    const txt = [
      '[A] [garbled timestamp] hello',
      '[A] [2024. 3. 15. 오후 2:34] world',
    ].join('\n');
    const out = parseKakaoExport(txt);
    expect(out.errors.length).toBeGreaterThan(0);
    expect(out.messages.some((m) => m.body === 'world')).toBe(true);
  });
});
