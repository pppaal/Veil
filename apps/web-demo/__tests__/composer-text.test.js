import { describe, expect, it } from 'vitest';

import {
  completeMention,
  isValidHandle,
  mentionAt,
  mentionCandidates,
  MESSAGE_MAX_CHARS,
  normalizeHandle,
} from '../src/domain/composer-text.js';

describe('handles', () => {
  it('are trimmed and lowered, then checked against the server rule', () => {
    expect(normalizeHandle('  Alice_1 ')).toBe('alice_1');
    expect(isValidHandle('alice_1')).toBe(true);
    for (const bad of ['', 'bad-handle', 'with space', 'a'.repeat(33), 'Upper']) expect(isValidHandle(bad)).toBe(false);
    expect(isValidHandle('a'.repeat(32))).toBe(true);
  });

  it('cap a message at 8000 characters', () => {
    expect(MESSAGE_MAX_CHARS).toBe(8000);
  });
});

describe('mentionAt', () => {
  it('finds the "@prefix" the caret follows at the start or after whitespace or punctuation', () => {
    expect(mentionAt('@al')).toEqual({ start: 0, prefix: 'al' });
    expect(mentionAt('hi @bo')).toEqual({ start: 3, prefix: 'bo' });
    expect(mentionAt('(@ca')).toEqual({ start: 1, prefix: 'ca' });
    expect(mentionAt('hi @')).toEqual({ start: 3, prefix: '' });
  });

  it('reads only up to the caret', () => {
    expect(mentionAt('@alice and more', 3)).toEqual({ start: 0, prefix: 'al' });
  });

  it('is nothing in an email address, after whitespace, or without an @', () => {
    expect(mentionAt('mail@host')).toBeNull();
    expect(mentionAt('@alice done')).toBeNull();
    expect(mentionAt('plain text')).toBeNull();
  });
});

describe('mentionCandidates', () => {
  const members = [
    { userId: 'u-me', handle: 'alfred' },
    { userId: 'u1', handle: 'Alice' },
    { userId: 'u2', handle: 'bob' },
    ...Array.from({ length: 8 }, (_, i) => ({ userId: `u${i + 3}`, handle: `al${i}` })),
  ];

  it('lists up to six other members whose handle starts with the prefix, case-insensitively', () => {
    const found = mentionCandidates(members, 'u-me', 'AL');
    expect(found).toHaveLength(6);
    expect(found[0].handle).toBe('Alice');
    expect(found.some((member) => member.userId === 'u-me')).toBe(false);
    expect(mentionCandidates(members, 'u-me', 'b').map((member) => member.handle)).toEqual(['bob']);
  });
});

describe('completeMention', () => {
  it('replaces the prefix with the handle and a space, and puts the caret after it', () => {
    const value = 'hi @al and on';
    const mention = mentionAt(value, 6);
    expect(completeMention(value, 6, mention, 'alice')).toEqual({ value: 'hi @alice  and on', caret: 10 });
  });
});
