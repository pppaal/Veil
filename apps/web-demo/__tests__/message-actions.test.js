// The delete dialog says a copy already received may stay: in a 1:1 of the
// one person there, in a group of everyone who got it.

import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

import { deleteBodyKey } from '../src/ui/views/message-actions.js';

const strings = JSON.parse(readFileSync(new URL('../i18n/en.json', import.meta.url), 'utf8'));

describe('the delete dialog body', () => {
  it('speaks of them in a 1:1 and of people in a group', () => {
    expect(strings[deleteBodyKey({ type: 'direct' })]).toBe('If they already got it, they may still see it.');
    expect(strings[deleteBodyKey({ type: 'group' })]).toBe('People who already got it may still see it.');
    expect(strings[deleteBodyKey(undefined)]).toBe('People who already got it may still see it.');
  });
});
