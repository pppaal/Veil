import { randomUUID } from 'node:crypto';

import { ConversationAccessService } from '../../common/conversation-access/conversation-access.service';
import { FakePrismaService } from '../../../test/support/fake-prisma.service';
import {
  FakePushService,
  FakeRealtimeGateway,
  FakeSafetyService,
} from '../../../test/support/fake-services';
import { ConversationsService } from '../conversations/conversations.service';
import { SendMessageDto } from './dto/send-message.dto';
import { MessagesService } from './messages.service';

type Actor = { userId: string; deviceId: string };

function makeService(options: { isProduction?: boolean } = {}) {
  const prisma = new FakePrismaService();
  const gateway = new FakeRealtimeGateway();
  const push = new FakePushService();
  const safety = new FakeSafetyService();
  const metrics = { messagesSentTotal: { inc: jest.fn() } };
  const access = new ConversationAccessService(prisma as never, safety as never);
  const service = new MessagesService(
    prisma as never,
    push as never,
    gateway as never,
    safety as never,
    metrics as never,
    access,
    { isProduction: options.isProduction ?? false } as never,
  );
  const conversations = new ConversationsService(
    prisma as never,
    gateway as never,
    safety as never,
    access,
  );
  return { prisma, gateway, push, safety, metrics, service, conversations };
}

function buildSendDto(overrides: {
  conversationId: string;
  sender: Actor;
  recipientUserId?: string;
  clientMessageId?: string;
  version?: string;
  messageType?: string;
  expiresAt?: string | null;
  viewOnce?: boolean;
  attachment?: Record<string, unknown>;
  replyToMessageId?: string;
  groupEpoch?: number;
}): SendMessageDto {
  return {
    conversationId: overrides.conversationId,
    clientMessageId:
      overrides.clientMessageId ?? `client-${randomUUID().replace(/-/g, '').slice(0, 16)}`,
    groupEpoch: overrides.groupEpoch,
    replyToMessageId: overrides.replyToMessageId,
    envelope: {
      version: overrides.version ?? 'veil-envelope-v1',
      conversationId: overrides.conversationId,
      senderDeviceId: overrides.sender.deviceId,
      recipientUserId: overrides.recipientUserId,
      ciphertext: 'ciphertext-blob',
      nonce: 'aaaaaaaaaaaaaaaaaaaaaaaa',
      messageType: overrides.messageType ?? 'text',
      expiresAt: overrides.expiresAt ?? null,
      viewOnce: overrides.viewOnce,
      attachment: overrides.attachment ?? null,
    },
  } as SendMessageDto;
}

function seedAttachment(
  prisma: FakePrismaService,
  uploaderDeviceId: string,
  uploadStatus: 'pending' | 'uploaded' | 'failed' = 'uploaded',
): string {
  const attachmentId = randomUUID();
  prisma.attachments.push({
    id: attachmentId,
    uploaderDeviceId,
    storageKey: `attachments/${attachmentId}`,
    contentType: 'application/octet-stream',
    sizeBytes: 1024,
    sha256: 'a'.repeat(64),
    uploadStatus,
    createdAt: new Date(),
  });
  return attachmentId;
}

const legacyAttachmentBlock = (attachmentId: string, algorithmHint = 'x25519-aes256gcm') => ({
  attachmentId,
  storageKey: `attachments/${attachmentId}`,
  contentType: 'image/jpeg',
  sizeBytes: 2048,
  sha256: 'b'.repeat(64),
  encryption: { encryptedKey: 'wrapped-key', nonce: 'wrap-nonce', algorithmHint },
});

function directFixture(options: { isProduction?: boolean } = {}) {
  const fixture = makeService(options);
  const alice = fixture.prisma.seedUser('alice');
  const bob = fixture.prisma.seedUser('bob');
  const conversationId = fixture.prisma.seedConversation('direct', [alice.userId, bob.userId]);
  const sendFromAlice = (overrides: Partial<Parameters<typeof buildSendDto>[0]> = {}) =>
    fixture.service.send(
      alice,
      buildSendDto({ conversationId, sender: alice, recipientUserId: bob.userId, ...overrides }),
    );
  return { ...fixture, alice, bob, conversationId, sendFromAlice };
}

describe('MessagesService', () => {
  describe('send', () => {
    it('persists the message and emits realtime events to the peer', async () => {
      const { prisma, gateway, metrics, alice, bob, conversationId, sendFromAlice } =
        directFixture();

      const result = await sendFromAlice();

      expect(result.idempotent).toBe(false);
      expect(result.message.conversationId).toBe(conversationId);
      expect(prisma.messages).toHaveLength(1);
      const emittedToBob = gateway.emitted.filter((entry) => entry.userId === bob.userId);
      expect(emittedToBob.map((entry) => entry.event)).toEqual([
        'message.new',
        'conversation.sync',
      ]);
      expect(
        gateway.emitted.some((e) => e.userId === alice.userId && e.event === 'message.new'),
      ).toBe(false);
      expect(metrics.messagesSentTotal.inc).toHaveBeenCalledWith({ message_type: 'text' });
    });

    it('rejects when envelope senderDeviceId does not match auth device', async () => {
      const { service, alice, bob, conversationId } = directFixture();

      await expect(
        service.send(
          alice,
          buildSendDto({ conversationId, sender: bob, recipientUserId: bob.userId }),
        ),
      ).rejects.toMatchObject({ status: 403, response: { code: 'envelope_context_mismatch' } });
    });

    it('rejects when the sender is not a conversation member', async () => {
      const { service, prisma, bob, conversationId } = directFixture();
      const mallory = prisma.seedUser('mallory');

      await expect(
        service.send(
          mallory,
          buildSendDto({ conversationId, sender: mallory, recipientUserId: bob.userId }),
        ),
      ).rejects.toMatchObject({
        status: 403,
        response: { code: 'conversation_membership_required' },
      });
    });

    it('is idempotent by clientMessageId', async () => {
      const { prisma, sendFromAlice } = directFixture();

      const first = await sendFromAlice({ clientMessageId: 'client-dedupe-test' });
      const second = await sendFromAlice({ clientMessageId: 'client-dedupe-test' });

      expect(first.idempotent).toBe(false);
      expect(second.idempotent).toBe(true);
      expect(second.message.id).toBe(first.message.id);
      expect(prisma.messages).toHaveLength(1);
    });

    it('rejects when direct envelope recipientUserId does not match the peer', async () => {
      const { prisma, sendFromAlice } = directFixture();
      const eve = prisma.seedUser('eve');

      await expect(sendFromAlice({ recipientUserId: eve.userId })).rejects.toMatchObject({
        status: 403,
        response: { code: 'direct_peer_mismatch' },
      });
    });

    it('refuses to send to a peer blocked in either direction', async () => {
      const { safety, alice, bob, prisma, sendFromAlice } = directFixture();
      safety.setBlocked(bob.userId, alice.userId);

      await expect(sendFromAlice()).rejects.toMatchObject({
        status: 403,
        response: { code: 'peer_unreachable' },
      });
      expect(prisma.messages).toHaveLength(0);
    });

    it('dispatches push fallback only to recipients that are not connected', async () => {
      const fixture = makeService();
      const alice = fixture.prisma.seedUser('alice');
      const bob = fixture.prisma.seedUser('bob', { pushToken: 'bob-device-token' });
      const conversationId = fixture.prisma.seedConversation('direct', [alice.userId, bob.userId]);
      const send = () =>
        fixture.service.send(
          alice,
          buildSendDto({ conversationId, sender: alice, recipientUserId: bob.userId }),
        );

      await send();
      expect(fixture.push.sentHints).toEqual([
        { pushToken: 'bob-device-token', hint: { kind: 'wake' } },
      ]);

      fixture.gateway.connectedUsers.add(bob.userId);
      fixture.gateway.connectedDevices.add(bob.deviceId);
      await send();
      expect(fixture.push.sentHints).toHaveLength(1);
    });

    it('malformed conversation id 400 not 500', async () => {
      const { service, alice, bob } = directFixture();

      await expect(
        service.send(
          alice,
          buildSendDto({
            conversationId: 'not-a-uuid',
            sender: alice,
            recipientUserId: bob.userId,
          }),
        ),
      ).rejects.toMatchObject({ status: 400, response: { code: 'validation_failed' } });
    });

    it('client messageType system accepted', async () => {
      const { prisma, sendFromAlice } = directFixture();

      const result = await sendFromAlice({ messageType: 'system' });

      expect(result.message.messageType).toBe('system');
      expect(prisma.messages[0]?.messageType).toBe('system');
    });
  });

  describe('envelope versions', () => {
    it('veil-group-v1 persisted and returned by send, list, realtime message.new and edit', async () => {
      const { service, conversations, prisma, gateway } = makeService();
      const alice = prisma.seedUser('alice');
      const bob = prisma.seedUser('bob');
      const conversationId = prisma.seedConversation('group', [alice.userId, bob.userId], {
        groupUseSenderKeys: true,
        currentEpoch: 2,
      });

      const sent = await service.send(
        alice,
        buildSendDto({ conversationId, sender: alice, version: 'veil-group-v1', groupEpoch: 2 }),
      );
      const listed = await conversations.listMessagesForUser(bob, conversationId, { limit: 50 });
      const realtime = gateway.emitted.find(
        (entry) => entry.userId === bob.userId && entry.event === 'message.new',
      );
      const edited = await service.edit(alice, sent.message.id, {
        ciphertext: 'ciphertext-v2',
        nonce: 'nonce-v2',
        version: 'veil-group-v1',
      });

      expect(prisma.messages[0]?.envelopeVersion).toBe('veil-group-v1');
      expect(sent.message.version).toBe('veil-group-v1');
      expect(listed.items[0]?.version).toBe('veil-group-v1');
      expect((realtime?.payload as { version: string }).version).toBe('veil-group-v1');
      expect(edited.message.version).toBe('veil-group-v1');
    });

    it('direct rejects veil-group-v1', async () => {
      const { prisma, sendFromAlice } = directFixture();

      await expect(sendFromAlice({ version: 'veil-group-v1' })).rejects.toMatchObject({
        status: 400,
        response: { code: 'envelope_version_mismatch' },
      });
      expect(prisma.messages).toHaveLength(0);
    });

    it('sender-keys group rejects veil-envelope-v2', async () => {
      const { service, prisma } = makeService();
      const alice = prisma.seedUser('alice');
      const bob = prisma.seedUser('bob');
      const conversationId = prisma.seedConversation('group', [alice.userId, bob.userId], {
        groupUseSenderKeys: true,
      });

      await expect(
        service.send(
          alice,
          buildSendDto({
            conversationId,
            sender: alice,
            version: 'veil-envelope-v2',
            groupEpoch: 0,
          }),
        ),
      ).rejects.toMatchObject({ status: 400, response: { code: 'envelope_version_mismatch' } });
    });

    it('legacy shared-key groups accept pairwise versions and refuse veil-group-v1', async () => {
      const { service, prisma } = makeService();
      const alice = prisma.seedUser('alice');
      const bob = prisma.seedUser('bob');
      const conversationId = prisma.seedConversation('group', [alice.userId, bob.userId]);

      const accepted = await service.send(
        alice,
        buildSendDto({ conversationId, sender: alice, version: 'veil-envelope-v2' }),
      );
      expect(accepted.message.version).toBe('veil-envelope-v2');
      await expect(
        service.send(
          alice,
          buildSendDto({ conversationId, sender: alice, version: 'veil-group-v1' }),
        ),
      ).rejects.toMatchObject({ response: { code: 'envelope_version_mismatch' } });
    });

    it('veil-envelope-v2 accepted in direct', async () => {
      const { prisma, sendFromAlice } = directFixture();

      const result = await sendFromAlice({ version: 'veil-envelope-v2' });

      expect(result.message.version).toBe('veil-envelope-v2');
      expect(prisma.messages[0]?.envelopeVersion).toBe('veil-envelope-v2');
    });

    it('production rejects veil-envelope-v1-dev and dev-wrap', async () => {
      const { prisma, alice, sendFromAlice } = directFixture({ isProduction: true });
      const attachmentId = seedAttachment(prisma, alice.deviceId);

      await expect(sendFromAlice({ version: 'veil-envelope-v1-dev' })).rejects.toMatchObject({
        status: 400,
        response: { code: 'envelope_version_forbidden' },
      });
      await expect(
        sendFromAlice({ attachment: legacyAttachmentBlock(attachmentId, 'dev-wrap') }),
      ).rejects.toMatchObject({ status: 400, response: { code: 'envelope_version_forbidden' } });
      expect(prisma.messages).toHaveLength(0);
    });

    it('accepts development envelopes outside production', async () => {
      const { sendFromAlice } = directFixture({ isProduction: false });

      const result = await sendFromAlice({ version: 'veil-envelope-v1-dev' });

      expect(result.message.version).toBe('veil-envelope-v1-dev');
    });
  });

  describe('group epoch gate', () => {
    const senderKeysGroup = (currentEpoch: number) => {
      const fixture = makeService();
      const alice = fixture.prisma.seedUser('alice');
      const bob = fixture.prisma.seedUser('bob');
      const conversationId = fixture.prisma.seedConversation('group', [alice.userId, bob.userId], {
        groupUseSenderKeys: true,
        currentEpoch,
      });
      const send = (groupEpoch?: number) =>
        fixture.service.send(
          alice,
          buildSendDto({ conversationId, sender: alice, version: 'veil-group-v1', groupEpoch }),
        );
      return { ...fixture, send };
    };

    it('accepts a group send carrying the current epoch when sender keys are on', async () => {
      const { prisma, send } = senderKeysGroup(5);

      const result = await send(5);

      expect(result.idempotent).toBe(false);
      expect(prisma.messages).toHaveLength(1);
    });

    it('rejects a group send under a stale epoch with group_epoch_stale', async () => {
      const { prisma, send } = senderKeysGroup(6);

      await expect(send(5)).rejects.toMatchObject({
        status: 409,
        response: { code: 'group_epoch_stale' },
      });
      expect(prisma.messages).toHaveLength(0);
    });

    it('rejects a group send with no epoch when sender keys are on', async () => {
      const { prisma, send } = senderKeysGroup(0);

      await expect(send(undefined)).rejects.toMatchObject({
        status: 400,
        response: { code: 'group_epoch_required' },
      });
      expect(prisma.messages).toHaveLength(0);
    });

    it('ignores the epoch gate for a legacy group that has not opted in', async () => {
      const { service, prisma } = makeService();
      const alice = prisma.seedUser('alice');
      const bob = prisma.seedUser('bob');
      const conversationId = prisma.seedConversation('group', [alice.userId, bob.userId], {
        currentEpoch: 9,
      });

      const result = await service.send(alice, buildSendDto({ conversationId, sender: alice }));

      expect(result.idempotent).toBe(false);
      expect(prisma.messages).toHaveLength(1);
    });
  });

  describe('channels', () => {
    const channelFixture = () => {
      const fixture = makeService();
      const owner = fixture.prisma.seedUser('owner');
      const subscriberA = fixture.prisma.seedUser('sub-a');
      const subscriberB = fixture.prisma.seedUser('sub-b');
      const conversationId = fixture.prisma.seedConversation(
        'channel',
        [
          { userId: owner.userId, role: 'owner' },
          { userId: subscriberA.userId, role: 'subscriber' },
          { userId: subscriberB.userId, role: 'subscriber' },
        ],
        { isPublic: true },
      );
      return { ...fixture, owner, subscriberA, subscriberB, conversationId };
    };

    it('subscriber send 403 conversation_role_required', async () => {
      const { service, prisma, subscriberA, conversationId } = channelFixture();

      await expect(
        service.send(subscriberA, buildSendDto({ conversationId, sender: subscriberA })),
      ).rejects.toMatchObject({ status: 403, response: { code: 'conversation_role_required' } });
      expect(prisma.messages).toHaveLength(0);
    });

    it('channel post creates zero receipts and markRead emits nothing', async () => {
      const { service, prisma, gateway, owner, subscriberA, conversationId } = channelFixture();

      const post = await service.send(owner, buildSendDto({ conversationId, sender: owner }));
      expect(prisma.messageReceipts).toHaveLength(0);

      gateway.emitted.length = 0;
      const read = await service.markRead(subscriberA, post.message.id);

      expect(read.messageId).toBe(post.message.id);
      expect(gateway.emitted).toEqual([]);
      expect(prisma.messageReceipts).toHaveLength(0);
    });
  });

  describe('markRead', () => {
    it('creates a delivered+read receipt and emits realtime receipts', async () => {
      const { service, gateway, bob, sendFromAlice } = directFixture();
      const sent = await sendFromAlice();
      gateway.emitted.length = 0;

      const receipt = await service.markRead(bob, sent.message.id);

      expect(receipt.messageId).toBe(sent.message.id);
      expect(receipt.readAt).toBeTruthy();
      expect(gateway.emitted.map((e) => e.event)).toEqual(
        expect.arrayContaining(['message.delivered', 'message.read']),
      );
    });

    it('group read receipt emitted only to sender and reader', async () => {
      const { service, prisma, gateway } = makeService();
      const alice = prisma.seedUser('alice');
      const bob = prisma.seedUser('bob');
      const carol = prisma.seedUser('carol');
      const conversationId = prisma.seedConversation('group', [
        alice.userId,
        bob.userId,
        carol.userId,
      ]);
      const sent = await service.send(alice, buildSendDto({ conversationId, sender: alice }));
      gateway.emitted.length = 0;

      await service.markRead(bob, sent.message.id);

      const receiptEvents = gateway.emitted.filter(
        (e) => e.event === 'message.read' || e.event === 'message.delivered',
      );
      expect(receiptEvents).toHaveLength(4);
      expect(new Set(receiptEvents.map((e) => e.userId))).toEqual(
        new Set([alice.userId, bob.userId]),
      );
      expect(gateway.emitted.some((e) => e.userId === carol.userId)).toBe(false);
    });

    it('refuses markRead for non-members', async () => {
      const { service, prisma, sendFromAlice } = directFixture();
      const mallory = prisma.seedUser('mallory');
      const sent = await sendFromAlice();

      await expect(service.markRead(mallory, sent.message.id)).rejects.toMatchObject({
        status: 403,
        response: { code: 'conversation_membership_required' },
      });
    });

    it('does not re-emit delivered/read when receipt already has both', async () => {
      const { service, gateway, bob, sendFromAlice } = directFixture();
      const sent = await sendFromAlice();
      await service.markRead(bob, sent.message.id);
      gateway.emitted.length = 0;

      await service.markRead(bob, sent.message.id);

      expect(gateway.emitted).toHaveLength(0);
    });

    it('reading your own message records no receipt', async () => {
      const { service, prisma, gateway, alice, sendFromAlice } = directFixture();
      const sent = await sendFromAlice();
      gateway.emitted.length = 0;
      const receiptsBefore = prisma.messageReceipts.length;

      await service.markRead(alice, sent.message.id);

      expect(prisma.messageReceipts).toHaveLength(receiptsBefore);
      expect(gateway.emitted).toHaveLength(0);
    });

    it('receipts do not reach a blocked direct peer', async () => {
      const { service, prisma, gateway, safety, alice, bob, sendFromAlice } = directFixture();
      const sent = await sendFromAlice();
      safety.setBlocked(bob.userId, alice.userId);
      gateway.emitted.length = 0;

      await service.markRead(bob, sent.message.id);

      expect(gateway.emitted.map((e) => [e.userId, e.event])).toEqual([
        [bob.userId, 'message.delivered'],
        [bob.userId, 'message.read'],
      ]);
      expect(prisma.messageReceipts).toEqual([
        expect.objectContaining({ userId: bob.userId, readAt: expect.any(Date) }),
      ]);
    });
  });

  describe('edit and delete', () => {
    it('edits within the window and broadcasts message.edited without receipts', async () => {
      const { service, gateway, alice, bob, sendFromAlice } = directFixture();
      const sent = await sendFromAlice();
      await service.markRead(bob, sent.message.id);
      gateway.emitted.length = 0;

      const edited = await service.edit(alice, sent.message.id, {
        ciphertext: 'ciphertext-v2',
        nonce: 'nonce-v2',
        version: 'veil-envelope-v1',
      });

      expect(edited.message.ciphertext).toBe('ciphertext-v2');
      expect(edited.message.editCount).toBe(1);
      const broadcast = gateway.emitted.filter((e) => e.event === 'message.edited');
      expect(broadcast.map((e) => e.userId).sort()).toEqual([alice.userId, bob.userId].sort());
      expect(broadcast[0]?.payload).toMatchObject({ deliveredAt: null, readAt: null });
    });

    it('ex-member edit 403', async () => {
      const { service, prisma } = makeService();
      const alice = prisma.seedUser('alice');
      const bob = prisma.seedUser('bob');
      const conversationId = prisma.seedConversation('group', [alice.userId, bob.userId]);
      const sent = await service.send(alice, buildSendDto({ conversationId, sender: alice }));
      prisma.conversationMembers = prisma.conversationMembers.filter(
        (member) => member.userId !== alice.userId,
      );

      await expect(
        service.edit(alice, sent.message.id, {
          ciphertext: 'ciphertext-v2',
          nonce: 'nonce-v2',
          version: 'veil-envelope-v1',
        }),
      ).rejects.toMatchObject({
        status: 403,
        response: { code: 'conversation_membership_required' },
      });
    });

    it('edit after 24h 403 edit_window_expired', async () => {
      const { service, prisma, alice, sendFromAlice } = directFixture();
      const sent = await sendFromAlice();
      prisma.messages[0]!.serverReceivedAt = new Date(Date.now() - 25 * 60 * 60 * 1000);

      await expect(
        service.edit(alice, sent.message.id, {
          ciphertext: 'ciphertext-v2',
          nonce: 'nonce-v2',
          version: 'veil-envelope-v1',
        }),
      ).rejects.toMatchObject({ status: 403, response: { code: 'edit_window_expired' } });
    });

    it('edit changing version 400', async () => {
      const { service, prisma, alice, sendFromAlice } = directFixture();
      const sent = await sendFromAlice({ version: 'veil-envelope-v2' });

      await expect(
        service.edit(alice, sent.message.id, {
          ciphertext: 'ciphertext-v2',
          nonce: 'nonce-v2',
          version: 'veil-envelope-v1',
        }),
      ).rejects.toMatchObject({ status: 400, response: { code: 'envelope_version_mismatch' } });
      expect(prisma.messages[0]?.ciphertext).toBe('ciphertext-blob');
    });

    it('only the sending device may edit or delete', async () => {
      const { service, bob, sendFromAlice } = directFixture();
      const sent = await sendFromAlice();

      await expect(
        service.edit(bob, sent.message.id, {
          ciphertext: 'x',
          nonce: 'y',
          version: 'veil-envelope-v1',
        }),
      ).rejects.toMatchObject({ status: 403, response: { code: 'message_not_owned' } });
      await expect(service.delete(bob, sent.message.id)).rejects.toMatchObject({
        status: 403,
        response: { code: 'message_not_owned' },
      });
    });

    it('delete tombstones the row and is idempotent', async () => {
      const { service, prisma, alice, sendFromAlice } = directFixture();
      const sent = await sendFromAlice();

      const first = await service.delete(alice, sent.message.id);
      const second = await service.delete(alice, sent.message.id);

      expect(second).toEqual(first);
      expect(prisma.messages[0]).toMatchObject({ ciphertext: 'deleted', attachmentRef: null });
    });

    it('blocked direct peer react/edit 403', async () => {
      const { service, safety, alice, bob, conversationId, sendFromAlice } = directFixture();
      const sent = await sendFromAlice();
      safety.setBlocked(alice.userId, bob.userId);

      await expect(
        service.send(
          bob,
          buildSendDto({
            conversationId,
            sender: bob,
            recipientUserId: alice.userId,
            messageType: 'reaction',
          }),
        ),
      ).rejects.toMatchObject({ status: 403, response: { code: 'peer_unreachable' } });
      await expect(
        service.edit(alice, sent.message.id, {
          ciphertext: 'ciphertext-v2',
          nonce: 'nonce-v2',
          version: 'veil-envelope-v1',
        }),
      ).rejects.toMatchObject({ status: 403, response: { code: 'peer_unreachable' } });
    });
  });

  describe('references', () => {
    it('cross-conversation replyTo 400', async () => {
      const { service, prisma, alice, bob, sendFromAlice } = directFixture();
      const carol = prisma.seedUser('carol');
      const otherConversation = prisma.seedConversation('direct', [alice.userId, carol.userId]);
      const elsewhere = await service.send(
        alice,
        buildSendDto({
          conversationId: otherConversation,
          sender: alice,
          recipientUserId: carol.userId,
        }),
      );

      await expect(
        sendFromAlice({ replyToMessageId: elsewhere.message.id, recipientUserId: bob.userId }),
      ).rejects.toMatchObject({ status: 400, response: { code: 'reply_target_invalid' } });
    });

    it('accepts a reply to a live message and rejects a reply to a deleted one', async () => {
      const { service, alice, sendFromAlice } = directFixture();
      const parent = await sendFromAlice();

      const reply = await sendFromAlice({ replyToMessageId: parent.message.id });
      expect(reply.message.replyToMessageId).toBe(parent.message.id);

      await service.delete(alice, parent.message.id);
      await expect(sendFromAlice({ replyToMessageId: parent.message.id })).rejects.toMatchObject({
        response: { code: 'reply_target_invalid' },
      });
    });

    it('pending attachment 400', async () => {
      const { prisma, alice, sendFromAlice } = directFixture();
      const attachmentId = seedAttachment(prisma, alice.deviceId, 'pending');

      await expect(sendFromAlice({ attachment: { attachmentId } })).rejects.toMatchObject({
        status: 400,
        response: { code: 'attachment_upload_invalid' },
      });
    });

    it('attachment uploaded by another user 403', async () => {
      const { prisma, bob, sendFromAlice } = directFixture();
      const attachmentId = seedAttachment(prisma, bob.deviceId);

      await expect(sendFromAlice({ attachment: { attachmentId } })).rejects.toMatchObject({
        status: 403,
        response: { code: 'attachment_forbidden' },
      });
    });

    it("accepts an attachment uploaded from another of the sender's devices", async () => {
      const { prisma, alice, sendFromAlice } = directFixture();
      const laptopDeviceId = prisma.seedDevice(alice.userId);
      const attachmentId = seedAttachment(prisma, laptopDeviceId);

      const result = await sendFromAlice({ attachment: { attachmentId } });

      expect(result.message.attachment).toEqual({ attachmentId });
    });

    it('rejects an unknown attachment', async () => {
      const { sendFromAlice } = directFixture();

      await expect(
        sendFromAlice({ attachment: { attachmentId: randomUUID() } }),
      ).rejects.toMatchObject({ status: 404, response: { code: 'attachment_not_found' } });
    });

    it('outer attachment persisted as attachmentId only', async () => {
      const { prisma, alice, sendFromAlice } = directFixture();
      const attachmentId = seedAttachment(prisma, alice.deviceId);

      const result = await sendFromAlice({ attachment: legacyAttachmentBlock(attachmentId) });

      expect(prisma.messages[0]?.attachmentRef).toEqual({ attachmentId });
      expect(prisma.messages[0]?.attachmentId).toBe(attachmentId);
      expect(result.message.attachment).toEqual({ attachmentId });
    });
  });

  describe('expiry', () => {
    const timerChat = (seconds: number) => {
      const fixture = makeService();
      const alice = fixture.prisma.seedUser('alice');
      const bob = fixture.prisma.seedUser('bob');
      const conversationId = fixture.prisma.seedConversation('direct', [alice.userId, bob.userId], {
        disappearingTimerSeconds: seconds,
      });
      const send = (expiresAt?: string | null) =>
        fixture.service.send(
          alice,
          buildSendDto({ conversationId, sender: alice, recipientUserId: bob.userId, expiresAt }),
        );
      return { ...fixture, send };
    };

    it('no expiresAt in 3600s timer chat stores ~now+3600', async () => {
      const { prisma, send } = timerChat(3600);
      const before = Date.now();

      await send(null);

      const storedAt = prisma.messages[0]!.expiresAt!.getTime();
      expect(storedAt).toBeGreaterThanOrEqual(before + 3600_000);
      expect(storedAt).toBeLessThanOrEqual(Date.now() + 3600_000);
    });

    it('expiresAt beyond timer clamped', async () => {
      const { prisma, send } = timerChat(3600);
      const before = Date.now();

      await send(new Date(before + 7 * 24 * 3600_000).toISOString());

      const storedAt = prisma.messages[0]!.expiresAt!.getTime();
      expect(storedAt).toBeGreaterThanOrEqual(before + 3600_000);
      expect(storedAt).toBeLessThanOrEqual(Date.now() + 3600_000);
    });

    it('keeps a client expiry that is shorter than the timer', async () => {
      const { prisma, send } = timerChat(3600);
      const requested = new Date(Date.now() + 600_000);

      await send(requested.toISOString());

      expect(prisma.messages[0]?.expiresAt?.getTime()).toBe(requested.getTime());
    });

    it('past expiresAt 400', async () => {
      const { prisma, sendFromAlice } = directFixture();

      await expect(
        sendFromAlice({ expiresAt: new Date(Date.now() - 5 * 60_000).toISOString() }),
      ).rejects.toMatchObject({ status: 400, response: { code: 'validation_failed' } });
      expect(prisma.messages).toHaveLength(0);
    });

    it('rejects an expiry more than 30 days ahead', async () => {
      const { sendFromAlice } = directFixture();

      await expect(
        sendFromAlice({ expiresAt: new Date(Date.now() + 31 * 24 * 3600_000).toISOString() }),
      ).rejects.toMatchObject({ status: 400, response: { code: 'validation_failed' } });
    });
  });

  describe('order counter', () => {
    it('m1,m2, view-once consume m2, m3.order == 3', async () => {
      const { service, prisma, bob, sendFromAlice } = directFixture();
      await sendFromAlice();
      const m2 = await sendFromAlice({ viewOnce: true });

      await service.markRead(bob, m2.message.id);
      expect(prisma.messages.map((m) => m.conversationOrder)).toEqual([1]);

      const m3 = await sendFromAlice();
      expect(m3.message.conversationOrder).toBe(3);
    });

    it('50 concurrent sends produce orders 1..50', async () => {
      const { sendFromAlice } = directFixture();

      const results = await Promise.all(Array.from({ length: 50 }, () => sendFromAlice()));

      const orders = results
        .map((result) => result.message.conversationOrder)
        .sort((a, b) => a - b);
      expect(orders).toEqual(Array.from({ length: 50 }, (_, index) => index + 1));
      expect(results.every((result) => !result.idempotent)).toBe(true);
    });

    it('a counter left behind by a pre-0017 writer resyncs instead of wedging sends', async () => {
      const { prisma, conversationId, sendFromAlice } = directFixture();
      await sendFromAlice();
      // An instance still on the old allocator inserts MAX()+1 without
      // touching last_order.
      prisma.messages.push({
        ...prisma.messages[0]!,
        id: randomUUID(),
        clientMessageId: 'legacy-allocator',
        conversationOrder: 2,
      });
      // Postgres rolls a failed send's increment back; the fake keeps it, so
      // restore it here to reproduce the wedge the resync has to break.
      const conversation = prisma.conversations.find((c) => c.id === conversationId)!;
      const transaction = prisma.$transaction.bind(prisma);
      prisma.$transaction = (async (callback: (tx: FakePrismaService) => Promise<unknown>) => {
        const lastOrderBefore = conversation.lastOrder;
        try {
          return await transaction(callback);
        } catch (error) {
          conversation.lastOrder = lastOrderBefore;
          throw error;
        }
      }) as typeof prisma.$transaction;

      const m3 = await sendFromAlice();
      const m4 = await sendFromAlice();

      expect([m3.message.conversationOrder, m4.message.conversationOrder]).toEqual([3, 4]);
      expect(conversation.lastOrder).toBe(4);
    });
  });

  describe('reactions', () => {
    // An offline recipient with a push token: anything that wakes devices
    // reaches FakePushService.
    const offlineRecipientFixture = () => {
      const fixture = makeService();
      const alice = fixture.prisma.seedUser('alice');
      const bob = fixture.prisma.seedUser('bob', { pushToken: 'bob-push-token' });
      const conversationId = fixture.prisma.seedConversation('direct', [alice.userId, bob.userId]);
      const sendFromAlice = (overrides: Partial<Parameters<typeof buildSendDto>[0]> = {}) =>
        fixture.service.send(
          alice,
          buildSendDto({
            conversationId,
            sender: alice,
            recipientUserId: bob.userId,
            ...overrides,
          }),
        );
      return { ...fixture, alice, bob, conversationId, sendFromAlice };
    };

    it('reaction envelope accepted and no push sent', async () => {
      const { prisma, gateway, push, bob, sendFromAlice } = offlineRecipientFixture();
      await sendFromAlice();
      push.sentHints.length = 0;
      gateway.emitted.length = 0;

      const reaction = await sendFromAlice({ messageType: 'reaction' });

      expect(reaction.idempotent).toBe(false);
      expect(reaction.message.messageType).toBe('reaction');
      // The relay stores the envelope as it came: it never parses the inner
      // {v, target, emoji, op} body, which only exists inside the ciphertext.
      const stored = prisma.messages.find((message) => message.id === reaction.message.id)!;
      expect(stored).toMatchObject({ messageType: 'reaction', ciphertext: 'ciphertext-blob' });
      expect(gateway.emitted.filter((e) => e.userId === bob.userId).map((e) => e.event)).toEqual([
        'message.new',
        'conversation.sync',
      ]);
      expect(push.sentHints).toEqual([]);
    });

    it('still wakes offline recipients for ordinary messages', async () => {
      const { push, sendFromAlice } = offlineRecipientFixture();

      await sendFromAlice({ messageType: 'text' });

      expect(push.sentHints).toEqual([{ pushToken: 'bob-push-token', hint: { kind: 'wake' } }]);
    });

    it('rejects reaction messages from non-members', async () => {
      const { service, prisma, conversationId, bob } = directFixture();
      const mallory = prisma.seedUser('mallory');

      await expect(
        service.send(
          mallory,
          buildSendDto({
            conversationId,
            sender: mallory,
            recipientUserId: bob.userId,
            messageType: 'reaction',
          }),
        ),
      ).rejects.toMatchObject({
        status: 403,
        response: { code: 'conversation_membership_required' },
      });
    });
  });

  describe('device activity', () => {
    afterEach(() => {
      jest.useRealTimers();
    });

    it('lastSyncAt truncated to day and not rewritten within the day', async () => {
      jest.useFakeTimers({ now: new Date('2026-11-11T09:30:15.123Z') });
      const { prisma, alice, sendFromAlice } = directFixture();
      const updateMany = jest.spyOn(prisma.device, 'updateMany');
      const lastSyncAt = () =>
        prisma.devices.find((candidate) => candidate.id === alice.deviceId)!.lastSyncAt;

      await sendFromAlice();
      const firstSync = lastSyncAt();
      expect(firstSync).toEqual(new Date('2026-11-11T00:00:00.000Z'));

      jest.setSystemTime(new Date('2026-11-11T23:59:59.999Z'));
      await sendFromAlice();
      expect(lastSyncAt()).toBe(firstSync);

      jest.setSystemTime(new Date('2026-11-12T00:00:00.001Z'));
      await sendFromAlice();
      expect(lastSyncAt()).toEqual(new Date('2026-11-12T00:00:00.000Z'));

      const writes = await Promise.all(
        updateMany.mock.results.map((result) => result.value as Promise<{ count: number }>),
      );
      expect(writes.map((write) => write.count)).toEqual([1, 0, 1]);
    });
  });

  describe('late group joiners', () => {
    const minutesAgo = (minutes: number) => new Date(Date.now() - minutes * 60_000);

    // Carol is added after both pre-join messages reached the relay.
    const lateJoinerGroup = async () => {
      const fixture = makeService();
      const { prisma, service } = fixture;
      const alice = prisma.seedUser('alice');
      const bob = prisma.seedUser('bob');
      const carol = prisma.seedUser('carol');
      const conversationId = prisma.seedConversation('group', [
        { userId: alice.userId, joinedAt: minutesAgo(30) },
        { userId: bob.userId, joinedAt: minutesAgo(30) },
      ]);
      const sendFromAlice = (overrides: Partial<Parameters<typeof buildSendDto>[0]> = {}) =>
        service.send(alice, buildSendDto({ conversationId, sender: alice, ...overrides }));

      const preJoin = await sendFromAlice();
      const preJoinViewOnce = await sendFromAlice({ viewOnce: true });
      for (const message of prisma.messages) {
        message.serverReceivedAt = minutesAgo(10);
      }
      prisma.conversationMembers.push({
        id: randomUUID(),
        conversationId,
        userId: carol.userId,
        role: 'member',
        joinedAt: minutesAgo(5),
      });
      fixture.gateway.emitted.length = 0;
      return { ...fixture, alice, bob, carol, sendFromAlice, preJoin, preJoinViewOnce };
    };

    const editTo = (ciphertext: string) => ({
      ciphertext,
      nonce: 'nonce-v2',
      version: 'veil-envelope-v1',
    });

    it('hides pre-join group messages from message-level actions', async () => {
      const { service, carol, preJoin } = await lateJoinerGroup();

      await expect(service.markRead(carol, preJoin.message.id)).rejects.toMatchObject({
        status: 404,
        response: { code: 'message_not_found' },
      });
    });

    it('late group joiner receives no message.edited for a pre-join message', async () => {
      const { service, gateway, alice, bob, carol, preJoin } = await lateJoinerGroup();

      await service.edit(alice, preJoin.message.id, editTo('edited-pre-join-ciphertext'));

      const edited = gateway.emitted.filter((e) => e.event === 'message.edited');
      expect(edited.map((e) => e.userId).sort()).toEqual([alice.userId, bob.userId].sort());
      expect(gateway.emitted.filter((e) => e.userId === carol.userId)).toEqual([]);
    });

    it('late group joiner receives no delete or consume event for pre-join messages', async () => {
      const { service, gateway, alice, bob, carol, preJoin, preJoinViewOnce } =
        await lateJoinerGroup();

      await service.delete(alice, preJoin.message.id);
      await service.markRead(bob, preJoinViewOnce.message.id);

      expect(new Set(gateway.emitted.map((e) => e.event))).toEqual(
        new Set(['message.deleted', 'message.delivered', 'message.read', 'message.consumed']),
      );
      expect(gateway.emitted.filter((e) => e.userId === carol.userId)).toEqual([]);
    });

    it('late group joiner receives events for messages sent after joining', async () => {
      const { service, gateway, alice, carol, sendFromAlice } = await lateJoinerGroup();
      const posted = await sendFromAlice();
      gateway.emitted.length = 0;

      await service.edit(alice, posted.message.id, editTo('edited-post-join-ciphertext'));
      await service.delete(alice, posted.message.id);

      expect(gateway.emitted.filter((e) => e.userId === carol.userId).map((e) => e.event)).toEqual([
        'message.edited',
        'message.deleted',
      ]);
    });
  });

  describe('deleteLocal', () => {
    it('acknowledges a delete for a member', async () => {
      const { service, bob, sendFromAlice } = directFixture();
      const sent = await sendFromAlice();

      const result = await service.deleteLocal(bob, sent.message.id);

      expect(result).toEqual({ messageId: sent.message.id, acknowledged: true });
    });

    it('rejects deleteLocal for non-members', async () => {
      const { service, prisma, sendFromAlice } = directFixture();
      const mallory = prisma.seedUser('mallory');
      const sent = await sendFromAlice();

      await expect(service.deleteLocal(mallory, sent.message.id)).rejects.toMatchObject({
        status: 403,
        response: { code: 'conversation_membership_required' },
      });
    });
  });
});
