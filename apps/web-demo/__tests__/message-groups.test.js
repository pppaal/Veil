import { describe, expect, it } from 'vitest';

import { DELIVERY_GLYPHS, DELIVERY_LABELS, deliveryStatus, groupMessages, GROUP_GAP_MS, sentAt } from '../src/domain/message-groups.js';

const me = { deviceId: 'd-me', handle: 'alice' };
const at = (minutes) => new Date(Date.UTC(2026, 0, 1, 10, minutes)).toISOString();
const message = (id, senderDeviceId, serverReceivedAt) => ({ id, senderDeviceId, serverReceivedAt });
const formatters = { dayKey: (date) => date.toISOString().slice(0, 10), dayLabel: (date) => `day ${date.toISOString().slice(0, 10)}` };

describe('groupMessages', () => {
  it('runs consecutive messages of one device within the gap together', () => {
    const days = groupMessages(
      [message('a', 'd-me', at(0)), message('b', 'd-me', at(1)), message('c', 'd-bob', at(1)), message('d', 'd-bob', at(5))],
      { me, peerHandle: 'bob', ...formatters },
    );
    expect(days).toHaveLength(1);
    expect(days[0].dayLabel).toBe('day 2026-01-01');
    expect(days[0].groups.map((group) => [group.senderHandle, group.isMe, group.msgs.map((m) => m.id)])).toEqual([
      ['alice', true, ['a', 'b']],
      ['bob', false, ['c']],
      ['bob', false, ['d']],
    ]);
  });

  it('starts a new day, and a new group in it', () => {
    const late = message('a', 'd-bob', '2026-01-01T23:59:00.000Z');
    const early = message('b', 'd-bob', '2026-01-02T00:00:30.000Z');
    const days = groupMessages([late, early], { me, peerHandle: 'bob', ...formatters });
    expect(days.map((day) => [day.dayKey, day.groups.length])).toEqual([['2026-01-01', 1], ['2026-01-02', 1]]);
  });

  it('dates a send the server has not acknowledged by its local time, and names an unknown peer "?"', () => {
    const pending = { id: 'p', senderDeviceId: 'd-x', serverReceivedAt: null, _localAt: at(3) };
    const [day] = groupMessages([pending], { me, peerHandle: undefined, ...formatters });
    expect(day.groups[0].senderHandle).toBe('?');
    expect(sentAt(pending, 0).toISOString()).toBe(at(3));
    expect(GROUP_GAP_MS).toBe(120_000);
  });
});

describe('deliveryStatus', () => {
  it('reads pending and failed sends, then receipts', () => {
    expect(deliveryStatus({ _status: 'pending', readAt: 'x' })).toBe('pending');
    expect(deliveryStatus({ _status: 'failed' })).toBe('failed');
    expect(deliveryStatus({ readAt: 'x', deliveredAt: 'y' })).toBe('read');
    expect(deliveryStatus({ deliveredAt: 'y' })).toBe('delivered');
    expect(deliveryStatus({})).toBe('sent');
  });

  it('has a glyph and a label for every state', () => {
    for (const status of ['pending', 'failed', 'read', 'delivered', 'sent']) {
      expect(DELIVERY_GLYPHS[status]).toBeTruthy();
      expect(DELIVERY_LABELS[status]).toBeTruthy();
    }
    expect(DELIVERY_LABELS.read).toBe('읽음');
    expect(DELIVERY_GLYPHS.sent).toBe('✓');
  });
});
