import { randomUUID } from 'node:crypto';

import { ConversationAccessService } from '../../common/conversation-access/conversation-access.service';
import { FakePrismaService } from '../../../test/support/fake-prisma.service';
import {
  FakeEphemeralStoreService,
  FakePushService,
  FakeRealtimeGateway,
  FakeSafetyService,
} from '../../../test/support/fake-services';
import { ChannelsService } from '../channels/channels.service';
import { ConversationsService } from '../conversations/conversations.service';
import { GroupsService } from '../groups/groups.service';
import { SendMessageDto } from './dto/send-message.dto';
import { toMessageSummary, type MessageSummaryRow } from './message.mapper';
import { MessagesService } from './messages.service';

function makeServices() {
  const prisma = new FakePrismaService();
  const gateway = new FakeRealtimeGateway();
  const safety = new FakeSafetyService();
  const access = new ConversationAccessService(prisma as never, safety as never);
  return {
    prisma,
    messages: new MessagesService(
      prisma as never,
      new FakePushService() as never,
      gateway as never,
      safety as never,
      { messagesSentTotal: { inc: () => undefined } } as never,
      access,
      { isProduction: false } as never,
    ),
    conversations: new ConversationsService(
      prisma as never,
      gateway as never,
      safety as never,
      access,
    ),
    groups: new GroupsService(
      prisma as never,
      gateway as never,
      new FakeEphemeralStoreService() as never,
      access,
      safety as never,
    ),
    channels: new ChannelsService(prisma as never, gateway as never, access),
  };
}

const sendDto = (
  conversationId: string,
  sender: { deviceId: string },
  recipientUserId?: string,
): SendMessageDto =>
  ({
    conversationId,
    clientMessageId: `client-${randomUUID().slice(0, 12)}`,
    envelope: {
      version: 'veil-envelope-v1',
      conversationId,
      senderDeviceId: sender.deviceId,
      recipientUserId,
      ciphertext: 'ciphertext-blob',
      nonce: 'nonce-blob',
      messageType: 'text',
    },
  }) as SendMessageDto;

const keysOf = (summary: object | null | undefined): string[] =>
  Object.keys(summary ?? { missing: true }).sort();

function row(overrides: Partial<MessageSummaryRow> = {}): MessageSummaryRow {
  return {
    id: randomUUID(),
    conversationId: randomUUID(),
    senderDeviceId: randomUUID(),
    clientMessageId: 'client-1',
    conversationOrder: 1,
    envelopeVersion: 'veil-envelope-v2',
    ciphertext: 'ct',
    nonce: 'nn',
    messageType: 'text',
    attachmentId: null,
    attachmentRef: null,
    serverReceivedAt: new Date('2026-01-01T00:00:00.000Z'),
    replyToMessageId: null,
    editedAt: null,
    editCount: 0,
    deletedAt: null,
    expiresAt: null,
    viewOnce: false,
    senderDevice: { userId: 'sender' },
    receipts: [],
    reactions: [],
    ...overrides,
  };
}

describe('message.mapper', () => {
  it('serves identical key sets for send, edit, list, conversation, group and channel lastMessage', async () => {
    const { prisma, messages, conversations, groups, channels } = makeServices();
    const alice = prisma.seedUser('alice');
    const bob = prisma.seedUser('bob');
    const directId = prisma.seedConversation('direct', [alice.userId, bob.userId]);
    const groupId = prisma.seedConversation('group', [alice.userId, bob.userId]);
    const channelId = prisma.seedConversation(
      'channel',
      [
        { userId: alice.userId, role: 'owner' },
        { userId: bob.userId, role: 'subscriber' },
      ],
      { isPublic: true },
    );

    const sent = await messages.send(alice, sendDto(directId, alice, bob.userId));
    const edited = await messages.edit(alice, sent.message.id, {
      ciphertext: 'ct-2',
      nonce: 'nn-2',
      version: 'veil-envelope-v1',
    });
    await messages.send(alice, sendDto(groupId, alice));
    await messages.send(alice, sendDto(channelId, alice));

    const listed = await conversations.listMessagesForUser(bob, directId, { limit: 50 });
    const conversationList = await conversations.listForUser(bob.userId);
    const group = await groups.getGroup({ ...bob, handle: 'bob' }, groupId);
    const channel = await channels.getChannel({ ...bob, handle: 'bob' }, channelId);

    const expected = keysOf(sent.message);
    expect(expected).toContain('version');
    expect(expected).toEqual(
      expect.arrayContaining(['editedAt', 'editCount', 'replyToMessageId', 'attachment']),
    );
    expect(keysOf(edited.message)).toEqual(expected);
    expect(keysOf(listed.items[0])).toEqual(expected);
    for (const summary of conversationList) {
      expect(keysOf(summary.lastMessage)).toEqual(expected);
    }
    expect(conversationList).toHaveLength(3);
    expect(keysOf(group.lastMessage)).toEqual(expected);
    expect(keysOf(channel.lastMessage)).toEqual(expected);
  });

  it('gives broadcast payloads null receipts even when the row has some', () => {
    const summary = toMessageSummary(
      row({
        receipts: [
          { userId: 'reader', deliveredAt: new Date(), readAt: new Date() },
          { userId: 'viewer', deliveredAt: new Date(), readAt: new Date() },
        ],
      }),
      { viewerUserId: 'viewer', broadcast: true },
    );

    expect(summary.deliveredAt).toBeNull();
    expect(summary.readAt).toBeNull();
  });

  it("takes receipt timestamps from the viewer's own receipt only", () => {
    const readAt = new Date('2026-01-02T00:00:00.000Z');
    const receipts = [{ userId: 'other-member', deliveredAt: readAt, readAt }];

    expect(toMessageSummary(row({ receipts }), { viewerUserId: 'sender' }).readAt).toBeNull();
    expect(toMessageSummary(row({ receipts }), { viewerUserId: 'other-member' }).readAt).toBe(
      readAt.toISOString(),
    );
  });

  it('reduces legacy attachment metadata to the outer pointer', () => {
    const attachmentId = randomUUID();
    const summary = toMessageSummary(
      row({
        attachmentId,
        attachmentRef: {
          attachmentId,
          storageKey: 'attachments/secret-layout',
          contentType: 'image/jpeg',
          sizeBytes: 4096,
          sha256: 'c'.repeat(64),
        },
      }),
    );

    expect(summary.attachment).toEqual({ attachmentId });
    expect(summary.version).toBe('veil-envelope-v2');
  });
});
