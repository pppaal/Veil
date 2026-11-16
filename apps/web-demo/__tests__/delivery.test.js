import { describe, expect, it } from 'vitest';

import { isPermanentRefusal, retryDelayMs } from '../src/domain/delivery.js';
import { isPendingId, pendingId } from '../src/domain/local-messages.js';
import { isMutedAt, muteDurationLabel, muteEntries, storedMutes } from '../src/domain/mute.js';

describe('outbound retries', () => {
  it('back off exponentially up to 30 seconds', () => {
    expect([1, 2, 3, 4, 5, 6].map(retryDelayMs)).toEqual([2000, 4000, 8000, 16000, 30000, 30000]);
  });

  it('give up on a 4xx refusal other than 429, and keep trying anything else', () => {
    expect(isPermanentRefusal({ status: 400 })).toBe(true);
    expect(isPermanentRefusal({ status: 404 })).toBe(true);
    for (const error of [{ status: 429 }, { status: 500 }, {}, null, new Error('offline')]) {
      expect(isPermanentRefusal(error)).toBe(false);
    }
  });
});

describe('local message ids', () => {
  it('mark a send the server has not named yet', () => {
    expect(pendingId('c-1')).toBe('__pending__c-1');
    expect(isPendingId(pendingId('c-1'))).toBe(true);
    expect(isPendingId('3f2a8c4e-0000-4000-8000-000000000000')).toBe(false);
    expect(isPendingId(undefined)).toBe(false);
  });
});

describe('mute durations', () => {
  it('are worded as the menu offers them: hours, weeks, or the units in between', () => {
    expect(muteDurationLabel(3600)).toBe('1 hour');
    expect(muteDurationLabel(8 * 3600)).toBe('8 hours');
    expect(muteDurationLabel(7 * 86400)).toBe('1 week');
    expect(muteDurationLabel(60)).toBe('1 minute');
    expect(muteDurationLabel(600)).toBe('10 minutes');
    expect(muteDurationLabel(86400 * 3)).toBe('3 days');
  });

  it('are stored with their end, read back without the ones that ended, and ids alone mean no end', () => {
    const now = 1_000_000;
    const stored = storedMutes(new Map([['c1', null], ['c2', now + 5000]]));
    expect(stored).toEqual(['c1', ['c2', now + 5000]]);
    expect([...muteEntries([...stored, ['c3', now - 1], 'c4', 42, ['c5', 'soon']], now)]).toEqual([['c1', null], ['c2', now + 5000], ['c4', null]]);
    expect(storedMutes(new Set(['c1']))).toEqual(['c1']);
    expect(muteEntries('{not a list', now).size).toBe(0);
    const mutes = muteEntries(stored, now);
    expect(isMutedAt(mutes, 'c2', now + 4999)).toBe(true);
    expect(isMutedAt(mutes, 'c2', now + 5000)).toBe(false);
    expect(isMutedAt(mutes, 'c1', now * 1000)).toBe(true);
  });
});
