// The handles an honest server issues, exactly the server's register
// grammar, and how one it could not have issued is shown.

import { readFileSync } from 'node:fs';

import { describe, expect, it } from 'vitest';

import {
  HANDLE_MAX_LENGTH,
  HANDLE_MIN_LENGTH,
  HandleRule,
  handleRuleBroken,
  isIssuableHandle,
  ISSUED_HANDLE_PATTERN,
  shownHandle,
} from '../src/domain/handles.js';
import { BOB_LOOKALIKES } from './support/lookalikes.js';

// What the registration form checks before it asks the server: the same
// grammar, rule by rule, so it can say which rule a handle breaks.
describe('handleRuleBroken', () => {
  it('names the first rule a handle breaks', () => {
    const cases = {
      '': HandleRule.CHARACTERS,
      ab: HandleRule.CHARACTERS,
      ['x'.repeat(33)]: HandleRule.CHARACTERS,
      'bad-handle': HandleRule.CHARACTERS,
      'with space': HandleRule.CHARACTERS,
      Bob: HandleRule.CHARACTERS,
      'bób': HandleRule.CHARACTERS,
      '..': HandleRule.CHARACTERS,
      '_bob': HandleRule.EDGES,
      'bob.': HandleRule.EDGES,
      '.b.': HandleRule.EDGES,
      'b..ob': HandleRule.RUN,
      'b._ob': HandleRule.RUN,
      'b__ob': HandleRule.RUN,
      'veil.operator': null,
      'a_b': null,
      '123': null,
      ['x'.repeat(32)]: null,
    };
    for (const [handle, rule] of Object.entries(cases)) expect(handleRuleBroken(handle), JSON.stringify(handle)).toBe(rule);
  });

  it('passes exactly the handles the server registers', () => {
    // Every string of up to 5 characters over an alphabet that reaches
    // each rule, and a few at the length limits.
    const alphabet = ['a', '1', '.', '_', '-', 'A'];
    let strings = [''];
    const all = [''];
    for (let length = 1; length <= 5; length += 1) {
      strings = strings.flatMap((prefix) => alphabet.map((character) => prefix + character));
      all.push(...strings);
    }
    all.push('a'.repeat(31) + '.', 'a'.repeat(31) + 'b', 'a.' + 'b'.repeat(30), 'a.' + 'b'.repeat(31));
    for (const handle of all) expect(handleRuleBroken(handle) === null, handle).toBe(isIssuableHandle(handle));
  });
});

describe('isIssuableHandle', () => {
  it('is the grammar the server registers handles in', () => {
    const dto = readFileSync(new URL('../../api/src/modules/auth/dto/register.dto.ts', import.meta.url), 'utf8');
    const [, min, max, pattern] = dto.match(/@Length\((\d+),\s*(\d+)\)\s*@Matches\((\/.+\/)\)\s*handle!: string;/);
    expect([Number(min), Number(max)]).toEqual([HANDLE_MIN_LENGTH, HANDLE_MAX_LENGTH]);
    expect(String(ISSUED_HANDLE_PATTERN)).toBe(pattern);
  });

  it('takes what the server issues, dots included', () => {
    for (const handle of ['bob', 'abc', '123', 'veil.operator', 'a_b', 'a1.b2_c3', 'x'.repeat(32)]) {
      expect(isIssuableHandle(handle), handle).toBe(true);
    }
  });

  it('refuses what it does not', () => {
    const refused = [
      ...Object.values(BOB_LOOKALIKES),
      'Bob',
      ' bob',
      'bob\n',
      'bob\u0000',
      'bób',
      '\u{1F600}bob',
      'ab',
      'x'.repeat(33),
      '.bob',
      'bob.',
      '_bob',
      'bob_',
      'b..ob',
      'b._ob',
      'b__ob',
      '',
      null,
      undefined,
      42,
    ];
    for (const handle of refused) expect(isIssuableHandle(handle), JSON.stringify(handle)).toBe(false);
  });
});

describe('shownHandle', () => {
  it('shows an issuable handle as it is', () => {
    expect(shownHandle('bob')).toBe('bob');
    expect(shownHandle('veil.operator')).toBe('veil.operator');
  });

  it('writes every character no handle can hold as its code point', () => {
    expect(shownHandle('bob​')).toBe('bob[U+200B]');
    expect(shownHandle('bоb')).toBe('b[U+043E]b');
    expect(shownHandle('‮bob')).toBe('[U+202E]bob');
    expect(shownHandle('bob ')).toBe('bob[U+0020]');
    expect(shownHandle('Bob')).toBe('[U+0042]ob');
    expect(shownHandle('\u{1F600}bob')).toBe('[U+1F600]bob');
    // Out of the grammar for its form, not its characters: it shows as it is.
    expect(shownHandle('b..ob')).toBe('b..ob');
  });

  it('never shows a lookalike as the handle it imitates', () => {
    for (const lookalike of Object.values(BOB_LOOKALIKES)) {
      expect(shownHandle(lookalike)).not.toBe('bob');
      expect(isIssuableHandle(shownHandle(lookalike))).toBe(false);
    }
  });

  it('shows no handle as ?', () => {
    // '?' is what the views write for no handle.
    expect(shownHandle('?')).toBe('?');
    expect(shownHandle('')).toBe('?');
    expect(shownHandle(undefined)).toBe('?');
    expect(shownHandle(null)).toBe('?');
  });
});
