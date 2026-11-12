import { describe, expect, it } from 'vitest';

import { highlightRuns, searchMatches, stepMatch } from '../src/domain/search.js';

const message = (id, kind, displayText, expiresAtMs = null) => ({ id, kind, displayText, expiresAtMs });

describe('searchMatches', () => {
  const messages = [
    message('m1', 'text', 'Hello Bob'),
    message('m2', 'reply', 'bob again'),
    message('m3', 'image', '🖼 bob'),
    message('m4', 'reaction', 'bob'),
    message('m5', 'text', 'bob expired', 500),
    message('m6', 'text', 'nothing here'),
  ];

  it('finds shown text messages containing the query, case-insensitively', () => {
    expect(searchMatches(messages, ' BOB ', 1_000).map((m) => m.id)).toEqual(['m1', 'm2']);
  });

  it('finds nothing for an empty query', () => {
    expect(searchMatches(messages, '   ', 1_000)).toEqual([]);
  });
});

describe('highlightRuns', () => {
  it('cuts the text around every occurrence, keeping its case', () => {
    expect(highlightRuns('Bob met bob', 'bob')).toEqual([
      { text: 'Bob', match: true },
      { text: ' met ', match: false },
      { text: 'bob', match: true },
    ]);
    expect(highlightRuns('no match', 'xyz')).toEqual([{ text: 'no match', match: false }]);
    expect(highlightRuns('', 'x')).toEqual([]);
  });
});

describe('stepMatch', () => {
  it('wraps forwards and backwards', () => {
    expect(stepMatch(2, 3)).toBe(0);
    expect(stepMatch(0, 3, true)).toBe(2);
    expect(stepMatch(1, 3)).toBe(2);
  });
});
