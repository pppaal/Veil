import type { ConversationType, MemberRole } from '@veil/shared';

export const CONVERSATION_ACTIONS = [
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
  'manageMembers',
] as const;
export type ConversationAction = (typeof CONVERSATION_ACTIONS)[number];

type RolePolicy = Readonly<Record<MemberRole, readonly ConversationAction[]>>;

const grant = (...actions: ConversationAction[]): readonly ConversationAction[] =>
  Object.freeze(actions);

const NOTHING = grant();
const DIRECT_MEMBER = grant(
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
);
const GROUP_MEMBER = grant(
  'send',
  'edit',
  'delete',
  'react',
  'typing',
  'setTimer',
  'readMembers',
  'readHistory',
  'markRead',
);
const GROUP_ADMIN = grant(...GROUP_MEMBER, 'manageMembers');
// A channel is a broadcast: subscribers only read, and only the owner and
// admins post or see who is subscribed.
const CHANNEL_SUBSCRIBER = grant('readHistory', 'markRead');
const CHANNEL_ADMIN = grant(
  'send',
  'edit',
  'delete',
  'setTimer',
  'readMembers',
  'readHistory',
  'markRead',
  'manageMembers',
);

// Roles that cannot occur in a conversation type (a direct "owner", a group
// "subscriber") are granted nothing, so a corrupted row fails closed.
export const POLICY: Readonly<Record<ConversationType, RolePolicy>> = Object.freeze({
  direct: Object.freeze({
    owner: NOTHING,
    admin: NOTHING,
    member: DIRECT_MEMBER,
    subscriber: NOTHING,
  }),
  group: Object.freeze({
    owner: GROUP_ADMIN,
    admin: GROUP_ADMIN,
    member: GROUP_MEMBER,
    subscriber: NOTHING,
  }),
  channel: Object.freeze({
    owner: CHANNEL_ADMIN,
    admin: CHANNEL_ADMIN,
    member: NOTHING,
    subscriber: CHANNEL_SUBSCRIBER,
  }),
});

// Whether delivered/read receipts exist at all. Channel receipts would tell
// every subscriber who else reads each post.
export const EMITS_RECEIPTS: Readonly<Record<ConversationType, boolean>> = Object.freeze({
  direct: true,
  group: true,
  channel: false,
});

// Actions that reach the peer of a direct conversation; an either-direction
// block makes the peer unreachable for them. Reading history, deleting your
// own message or changing the timer stay possible so a blocked pair can
// still tidy up their own copy of the conversation.
export const PEER_REACHING_ACTIONS: ReadonlySet<ConversationAction> = new Set<ConversationAction>([
  'send',
  'edit',
  'react',
  'typing',
  'call',
]);

export const isActionAllowed = (
  type: ConversationType,
  role: MemberRole,
  action: ConversationAction,
): boolean => POLICY[type][role].includes(action);

/**
 * The earliest message a member may see. Group members only see messages
 * received after they joined, so an added member cannot read (or mark
 * delivered) the backlog. Direct conversations have no join history, and a
 * channel is a public broadcast whose backlog is part of what subscribers
 * sign up for, so both are unrestricted.
 */
export const historyVisibleSince = (type: ConversationType, joinedAt: Date): Date | null =>
  type === 'group' ? joinedAt : null;
