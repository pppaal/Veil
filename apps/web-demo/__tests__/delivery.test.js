import { describe, expect, it } from 'vitest';

import { isPermanentRefusal, retryDelayMs } from '../src/domain/delivery.js';
import { isPendingId, pendingId } from '../src/domain/local-messages.js';
import { muteDurationLabel, muteSecondsFromMinutes } from '../src/domain/mute.js';

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
  it('are worded in minutes, hours, days or for good', () => {
    expect(muteDurationLabel(600)).toBe('10분');
    expect(muteDurationLabel(7200)).toBe('2시간');
    expect(muteDurationLabel(86400 * 3)).toBe('3일');
    expect(muteDurationLabel(86400 * 365)).toBe('영구');
  });

  it('come from the minutes typed, at least one, an hour for anything else', () => {
    expect(muteSecondsFromMinutes('90')).toBe(5400);
    expect(muteSecondsFromMinutes('0')).toBe(3600);
    expect(muteSecondsFromMinutes('-5')).toBe(60);
    expect(muteSecondsFromMinutes('soon')).toBe(3600);
  });
});
