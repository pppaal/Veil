// An abuse report matches the API's FileAbuseReportDto and carries no text
// the user typed, and it names the member who sent the message.

import { describe, expect, it } from 'vitest';

import { abuseReport, REPORT_REASONS, senderToReport } from '../src/features/report.js';

const ids = {
  reportedUserId: '6f0c1a2b-3d4e-4f50-8a9b-0c1d2e3f4a5b',
  conversationId: '0d4c1a2b-3d4e-4f50-8a9b-0c1d2e3f4a5c',
  messageId: '3b241101-e2bb-4255-8caf-4136c566a962',
};

describe('abuse reports', () => {
  it('send the reason and the ids, and nothing else', () => {
    // AbuseReportReason in packages/contracts.
    expect(REPORT_REASONS).toEqual(['spam', 'harassment', 'impersonation', 'csam', 'violence', 'scam', 'other']);
    for (const reason of REPORT_REASONS) {
      const body = abuseReport({ ...ids, reason, note: 'what they wrote', details: 'free text' });
      expect(body).toEqual({ ...ids, reason });
    }
    expect(() => abuseReport({ ...ids, reason: 'rude' })).toThrow(TypeError);
  });

  it('name the sender of a direct message, and nobody in a group or for our own message', () => {
    const self = { userId: 'u-alice', deviceId: 'd-alice' };
    const members = [{ userId: 'u-alice', handle: 'alice' }, { userId: 'u-bob', handle: 'bob' }, { userId: 'u-carol', handle: 'carol' }];
    const direct = { type: 'direct', members: members.slice(0, 2) };
    expect(senderToReport(direct, { senderDeviceId: 'd-bob' }, self)).toEqual({ userId: 'u-bob', handle: 'bob' });
    expect(senderToReport(direct, { senderDeviceId: 'd-alice' }, self)).toBeNull();
    expect(senderToReport({ type: 'group', members }, { senderDeviceId: 'd-carol' }, self)).toBeNull();
    expect(senderToReport(direct, { senderDeviceId: 'd-bob' }, { deviceId: 'd-alice' })).toBeNull();
  });
});
