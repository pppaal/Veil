import { conversationTypes, memberRoles } from '@veil/shared';

import {
  CONVERSATION_ACTIONS,
  EMITS_RECEIPTS,
  POLICY,
  historyVisibleSince,
  isActionAllowed,
  messageAudienceJoinedBy,
} from './conversation-policy';

// The complete authorization matrix, written out independently of the
// implementation. Every (type, role) pair not listed may do nothing.
const EXPECTED_GRANTS: Record<string, string[]> = {
  'direct/member': [
    'send',
    'edit',
    'delete',
    'react',
    'typing',
    'setTimer',
    'call',
    'readMembers',
    'readHistory',
    'markRead',
  ],
  'group/member': [
    'send',
    'edit',
    'delete',
    'react',
    'typing',
    'setTimer',
    'readMembers',
    'readHistory',
    'markRead',
  ],
  'group/admin': [
    'send',
    'edit',
    'delete',
    'react',
    'typing',
    'setTimer',
    'readMembers',
    'readHistory',
    'markRead',
    'manageMembers',
  ],
  'group/owner': [
    'send',
    'edit',
    'delete',
    'react',
    'typing',
    'setTimer',
    'readMembers',
    'readHistory',
    'markRead',
    'manageMembers',
  ],
  'channel/subscriber': ['readHistory', 'markRead'],
  'channel/admin': [
    'send',
    'edit',
    'delete',
    'setTimer',
    'readMembers',
    'readHistory',
    'markRead',
    'manageMembers',
  ],
  'channel/owner': [
    'send',
    'edit',
    'delete',
    'setTimer',
    'readMembers',
    'readHistory',
    'markRead',
    'manageMembers',
  ],
};

const table = conversationTypes.flatMap((type) =>
  memberRoles.flatMap((role) =>
    CONVERSATION_ACTIONS.map((action) => ({
      type,
      role,
      action,
      allowed: (EXPECTED_GRANTS[`${type}/${role}`] ?? []).includes(action),
    })),
  ),
);

describe('conversation policy', () => {
  it('covers every type x role x action combination', () => {
    expect(table).toHaveLength(3 * 4 * 11);
  });

  it.each(table)('$type/$role $action -> $allowed', ({ type, role, action, allowed }) => {
    expect(isActionAllowed(type, role, action)).toBe(allowed);
  });

  it('nobody can call outside direct conversations', () => {
    for (const type of ['group', 'channel'] as const) {
      for (const role of memberRoles) {
        expect(isActionAllowed(type, role, 'call')).toBe(false);
      }
    }
  });

  it('is frozen', () => {
    expect(Object.isFrozen(POLICY)).toBe(true);
    expect(Object.isFrozen(POLICY.channel)).toBe(true);
    expect(Object.isFrozen(POLICY.channel.subscriber)).toBe(true);
    expect(() => (POLICY.channel.subscriber as string[]).push('send')).toThrow(TypeError);
  });

  it('emits receipts everywhere except channels', () => {
    expect(EMITS_RECEIPTS).toEqual({ direct: true, group: true, channel: false });
  });

  it('limits history to the join time in groups only', () => {
    const joinedAt = new Date('2026-05-01T00:00:00.000Z');
    expect(historyVisibleSince('group', joinedAt)).toBe(joinedAt);
    expect(historyVisibleSince('direct', joinedAt)).toBeNull();
    expect(historyVisibleSince('channel', joinedAt)).toBeNull();
  });

  it('limits the audience of a message to members who could list it', () => {
    const receivedAt = new Date('2026-05-01T00:00:00.000Z');
    expect(messageAudienceJoinedBy('group', receivedAt)).toBe(receivedAt);
    expect(messageAudienceJoinedBy('direct', receivedAt)).toBeNull();
    expect(messageAudienceJoinedBy('channel', receivedAt)).toBeNull();
  });
});
