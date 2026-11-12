import { describe, expect, it } from 'vitest';

import { byLastActivity, directPeer, matchesSearch, previewMessage, shownPeer, snippetOf } from '../src/domain/conversations.js';

const alice = { userId: 'u-alice', handle: 'alice' };
const bob = { userId: 'u-bob', handle: 'bob' };
const direct = { id: 'c1', type: 'direct', members: [alice, bob], createdAt: '2026-01-01T00:00:00.000Z' };
const text = (id, displayText, extra = {}) => ({ id, kind: 'text', displayText, expiresAtMs: null, ...extra });

describe('directPeer', () => {
  it('is the other member of a direct conversation', () => {
    expect(directPeer(direct, alice.userId)).toBe(bob);
  });

  it('is nobody until a login has named us, in a group, or without a conversation', () => {
    expect(directPeer(direct, null)).toBeNull();
    expect(directPeer({ ...direct, type: 'group' }, alice.userId)).toBeNull();
    expect(directPeer(undefined, alice.userId)).toBeNull();
  });
});

describe('shownPeer', () => {
  it('names a conversation after a member other than us, else its first member', () => {
    expect(shownPeer(direct, 'alice')).toBe(bob);
    expect(shownPeer({ members: [alice] }, 'alice')).toBe(alice);
    expect(shownPeer({}, 'alice')).toBeUndefined();
  });
});

describe('byLastActivity', () => {
  it('puts the newest last message, or the newest creation, first', () => {
    const older = { createdAt: '2026-01-01T00:00:00.000Z', lastMessage: { serverReceivedAt: '2026-01-03T00:00:00.000Z' } };
    const newer = { createdAt: '2026-01-02T00:00:00.000Z', lastMessage: null };
    const newest = { createdAt: '2026-01-01T00:00:00.000Z', lastMessage: { serverReceivedAt: '2026-01-04T00:00:00.000Z' } };
    expect([newer, older, newest].sort(byLastActivity)).toEqual([newest, older, newer]);
  });
});

describe('matchesSearch', () => {
  it('matches a member handle containing the lowercased query, and everything for no query', () => {
    expect(matchesSearch(direct, '')).toBe(true);
    expect(matchesSearch(direct, 'bo')).toBe(true);
    expect(matchesSearch(direct, 'carol')).toBe(false);
  });
});

describe('previewMessage', () => {
  const now = 1_000;

  it('is the last message while it is shown', () => {
    const last = text('m2', 'latest');
    expect(previewMessage({ lastMessage: last }, [text('m1', 'older')], now)).toBe(last);
  });

  it('falls back to the newest loaded message a panel shows when the last is a reaction or gone', () => {
    const shown = text('m1', 'older');
    const reaction = { id: 'm2', kind: 'reaction', displayText: '💬 반응', expiresAtMs: null };
    const expired = text('m3', 'gone', { expiresAtMs: 500 });
    expect(previewMessage({ lastMessage: reaction }, [shown, reaction], now)).toBe(shown);
    expect(previewMessage({ lastMessage: expired }, [shown, expired], now)).toBe(shown);
  });

  it('keeps a reaction as the preview when nothing else shows, and nothing for a gone message', () => {
    const reaction = { id: 'm2', kind: 'reaction', displayText: '💬 반응', expiresAtMs: null };
    expect(previewMessage({ lastMessage: reaction }, [], now)).toBe(reaction);
    expect(previewMessage({ lastMessage: text('m3', 'gone', { expiresAtMs: 500 }) }, [], now)).toBeNull();
    expect(previewMessage({ lastMessage: null }, [], now)).toBeNull();
  });
});

describe('snippetOf', () => {
  it('cuts the preview label with an ellipsis', () => {
    expect(snippetOf(text('m1', 'hello world'), 5)).toBe('hello…');
    expect(snippetOf(text('m1', 'hello'), 5)).toBe('hello');
    expect(snippetOf({ id: 'm2', kind: 'image', displayText: '🖼 이미지', expiresAtMs: null }, 80)).toBe('🖼 이미지');
  });
});
