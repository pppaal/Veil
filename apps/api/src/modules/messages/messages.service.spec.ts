import { randomUUID } from 'node:crypto';

import { MessagesService } from './messages.service';
import { FakePrismaService } from '../../../test/support/fake-prisma.service';
import {
  FakePushService,
  FakeRealtimeGateway,
} from '../../../test/support/fake-services';
import { SendMessageDto } from './dto/send-message.dto';

type Seed = {
  prisma: FakePrismaService;
  gateway: FakeRealtimeGateway;
  push: FakePushService;
  service: MessagesService;
};

function makeService(): Seed {
  const prisma = new FakePrismaService();
  const gateway = new FakeRealtimeGateway();
  const push = new FakePushService();
  const service = new MessagesService(
    prisma as never,
    push as never,
    gateway as never,
  );
  return { prisma, gateway, push, service };
}

function seedUserAndDevice(
  prisma: FakePrismaService,
  handle = `user-${Math.random().toString(36).slice(2, 8)}`,
  options: { pushToken?: string | null } = {},
): { userId: string; deviceId: string } {
  const userId = randomUUID();
  const deviceId = randomUUID();
  prisma.users.push({
    id: userId,
    handle,
    displayName: handle,
    avatarPath: null,
    status: 'active',
    activeDeviceId: deviceId,
    createdAt: new Date(),
    updatedAt: new Date(),
  });
  prisma.devices.push({
    id: deviceId,
    userId,
    platform: 'ios',
    deviceName: 'Test',
    publicIdentityKey: 'pub-id',
    signedPrekeyBundle: 'prekey',
    authPublicKey: 'auth-pub',
    pushToken: options.pushToken ?? null,
    isActive: true,
    revokedAt: null,
    trustedAt: new Date(),
    joinedFromDeviceId: null,
    createdAt: new Date(),
    lastSeenAt: new Date(),
    lastSyncAt: null,
  });
  return { userId, deviceId };
}

function seedDirectConversation(
  prisma: FakePrismaService,
  aUserId: string,
  bUserId: string,
): string {
  const conversationId = randomUUID();
  prisma.conversations.push({
    id: conversationId,
    type: 'direct',
    createdAt: new Date(),
  });
  prisma.conversationMembers.push({
    id: randomUUID(),
    conversationId,
    userId: aUserId,
    joinedAt: new Date(),
  });
  prisma.conversationMembers.push({
    id: randomUUID(),
    conversationId,
    userId: bUserId,
    joinedAt: new Date(),
  });
  return conversationId;
}

function buildSendDto(overrides: {
  conversationId: string;
  senderDeviceId: string;
  recipientUserId?: string;
  clientMessageId?: string;
  ciphertext?: string;
  attachmentId?: string;
}): SendMessageDto {
  return {
    conversationId: overrides.conversationId,
    clientMessageId:
      overrides.clientMessageId ?? `client-${randomUUID().replace(/-/g, '').slice(0, 16)}`,
    envelope: {
      version: 'veil.v1',
      conversationId: overrides.conversationId,
      senderDeviceId: overrides.senderDeviceId,
      recipientUserId: overrides.recipientUserId,
      ciphertext: overrides.ciphertext ?? 'ciphertext-blob',
      nonce: 'aaaaaaaaaaaaaaaaaaaaaaaa',
      messageType: 'text',
      expiresAt: null,
      attachment: overrides.attachmentId
        ? {
            attachmentId: overrides.attachmentId,
            storageKey: `attachments/${overrides.attachmentId}`,
            contentType: 'application/octet-stream',
            sizeBytes: 1024,
            sha256: 'a'.repeat(64),
            encryption: {
              encryptedKey: 'key-material',
              nonce: 'nonce-material',
              algorithmHint: 'aes-256-gcm',
            },
          }
        : null,
    },
  } as SendMessageDto;
}

describe('MessagesService', () => {
  describe('send', () => {
    it('persists the message and emits realtime events to the peer', async () => {
      const { service, prisma, gateway } = makeService();
      const alice = seedUserAndDevice(prisma, 'alice');
      const bob = seedUserAndDevice(prisma, 'bob');
      const conversationId = seedDirectConversation(
        prisma,
        alice.userId,
        bob.userId,
      );

      const result = await service.send(
        { userId: alice.userId, deviceId: alice.deviceId },
        buildSendDto({
          conversationId,
          senderDeviceId: alice.deviceId,
          recipientUserId: bob.userId,
        }),
      );

      expect(result.idempotent).toBe(false);
      expect(result.message.conversationId).toBe(conversationId);
      expect(prisma.messages).toHaveLength(1);

      const emittedToBob = gateway.emitted.filter(
        (entry) => entry.userId === bob.userId,
      );
      expect(emittedToBob.some((e) => e.event === 'message.new')).toBe(true);
      expect(emittedToBob.some((e) => e.event === 'conversation.sync')).toBe(true);
    });

    it('rejects when envelope senderDeviceId does not match auth device', async () => {
      const { service, prisma } = makeService();
      const alice = seedUserAndDevice(prisma, 'alice');
      const bob = seedUserAndDevice(prisma, 'bob');
      const conversationId = seedDirectConversation(
        prisma,
        alice.userId,
        bob.userId,
      );

      await expect(
        service.send(
          { userId: alice.userId, deviceId: alice.deviceId },
          buildSendDto({
            conversationId,
            senderDeviceId: bob.deviceId,
            recipientUserId: bob.userId,
          }),
        ),
      ).rejects.toThrow('Envelope sender context mismatch');
    });

    it('rejects when the sender is not a conversation member', async () => {
      const { service, prisma } = makeService();
      const alice = seedUserAndDevice(prisma, 'alice');
      const bob = seedUserAndDevice(prisma, 'bob');
      const mallory = seedUserAndDevice(prisma, 'mallory');
      const conversationId = seedDirectConversation(
        prisma,
        alice.userId,
        bob.userId,
      );

      await expect(
        service.send(
          { userId: mallory.userId, deviceId: mallory.deviceId },
          buildSendDto({
            conversationId,
            senderDeviceId: mallory.deviceId,
            recipientUserId: bob.userId,
          }),
        ),
      ).rejects.toThrow('Conversation membership required');
    });

    it('is idempotent by clientMessageId', async () => {
      const { service, prisma } = makeService();
      const alice = seedUserAndDevice(prisma, 'alice');
      const bob = seedUserAndDevice(prisma, 'bob');
      const conversationId = seedDirectConversation(
        prisma,
        alice.userId,
        bob.userId,
      );

      const dto = buildSendDto({
        conversationId,
        senderDeviceId: alice.deviceId,
        recipientUserId: bob.userId,
        clientMessageId: 'client-dedupe-test',
      });

      const first = await service.send(
        { userId: alice.userId, deviceId: alice.deviceId },
        dto,
      );
      const second = await service.send(
        { userId: alice.userId, deviceId: alice.deviceId },
        dto,
      );

      expect(first.idempotent).toBe(false);
      expect(second.idempotent).toBe(true);
      expect(second.message.id).toBe(first.message.id);
      expect(prisma.messages).toHaveLength(1);
    });

    it('rejects attachment owned by a different device', async () => {
      const { service, prisma } = makeService();
      const alice = seedUserAndDevice(prisma, 'alice');
      const bob = seedUserAndDevice(prisma, 'bob');
      const conversationId = seedDirectConversation(
        prisma,
        alice.userId,
        bob.userId,
      );

      const attachmentId = randomUUID();
      prisma.attachments.push({
        id: attachmentId,
        uploaderDeviceId: bob.deviceId, // attachment owned by bob, not alice
        storageKey: `attachments/${attachmentId}`,
        contentType: 'application/octet-stream',
        sizeBytes: 1024,
        sha256: 'a'.repeat(64),
        uploadStatus: 'uploaded',
        uploadedAt: new Date(),
        createdAt: new Date(),
      } as never);

      await expect(
        service.send(
          { userId: alice.userId, deviceId: alice.deviceId },
          buildSendDto({
            conversationId,
            senderDeviceId: alice.deviceId,
            recipientUserId: bob.userId,
            attachmentId,
          }),
        ),
      ).rejects.toThrow('Attachment not found for sender device');
    });

    it('rejects when direct envelope recipientUserId does not match the peer', async () => {
      const { service, prisma } = makeService();
      const alice = seedUserAndDevice(prisma, 'alice');
      const bob = seedUserAndDevice(prisma, 'bob');
      const eve = seedUserAndDevice(prisma, 'eve');
      const conversationId = seedDirectConversation(
        prisma,
        alice.userId,
        bob.userId,
      );

      await expect(
        service.send(
          { userId: alice.userId, deviceId: alice.deviceId },
          buildSendDto({
            conversationId,
            senderDeviceId: alice.deviceId,
            recipientUserId: eve.userId,
          }),
        ),
      ).rejects.toThrow('Envelope recipient does not match direct conversation peer');
    });

    it('dispatches push fallback only to recipients that are not connected', async () => {
      const { service, prisma, gateway, push } = makeService();
      const alice = seedUserAndDevice(prisma, 'alice');
      const bob = seedUserAndDevice(prisma, 'bob', {
        pushToken: 'bob-device-token',
      });
      const conversationId = seedDirectConversation(
        prisma,
        alice.userId,
        bob.userId,
      );

      // Bob is offline → expect push hint
      await service.send(
        { userId: alice.userId, deviceId: alice.deviceId },
        buildSendDto({
          conversationId,
          senderDeviceId: alice.deviceId,
          recipientUserId: bob.userId,
        }),
      );

      expect(push.sentHints).toHaveLength(1);
      expect(push.sentHints[0].pushToken).toBe('bob-device-token');

      // Now mark Bob's device as connected and expect no new push hint
      gateway.connectedUsers.add(bob.userId);
      gateway.connectedDevices.add(bob.deviceId);

      await service.send(
        { userId: alice.userId, deviceId: alice.deviceId },
        buildSendDto({
          conversationId,
          senderDeviceId: alice.deviceId,
          recipientUserId: bob.userId,
        }),
      );

      expect(push.sentHints).toHaveLength(1); // unchanged
    });
  });

  describe('markRead', () => {
    it('creates a delivered+read receipt and emits realtime receipts', async () => {
      const { service, prisma, gateway } = makeService();
      const alice = seedUserAndDevice(prisma, 'alice');
      const bob = seedUserAndDevice(prisma, 'bob');
      const conversationId = seedDirectConversation(
        prisma,
        alice.userId,
        bob.userId,
      );

      const sent = await service.send(
        { userId: alice.userId, deviceId: alice.deviceId },
        buildSendDto({
          conversationId,
          senderDeviceId: alice.deviceId,
          recipientUserId: bob.userId,
        }),
      );

      gateway.emitted.length = 0;

      const receipt = await service.markRead(
        { userId: bob.userId, deviceId: bob.deviceId },
        sent.message.id,
      );

      expect(receipt.messageId).toBe(sent.message.id);
      expect(receipt.readAt).toBeTruthy();

      const delivered = gateway.emitted.find((e) => e.event === 'message.delivered');
      const read = gateway.emitted.find((e) => e.event === 'message.read');
      expect(delivered).toBeDefined();
      expect(read).toBeDefined();
    });

    it('refuses markRead for non-members', async () => {
      const { service, prisma } = makeService();
      const alice = seedUserAndDevice(prisma, 'alice');
      const bob = seedUserAndDevice(prisma, 'bob');
      const mallory = seedUserAndDevice(prisma, 'mallory');
      const conversationId = seedDirectConversation(
        prisma,
        alice.userId,
        bob.userId,
      );

      const sent = await service.send(
        { userId: alice.userId, deviceId: alice.deviceId },
        buildSendDto({
          conversationId,
          senderDeviceId: alice.deviceId,
          recipientUserId: bob.userId,
        }),
      );

      await expect(
        service.markRead(
          { userId: mallory.userId, deviceId: mallory.deviceId },
          sent.message.id,
        ),
      ).rejects.toThrow('Message not found for actor');
    });

    it('does not re-emit delivered/read when receipt already has both', async () => {
      const { service, prisma, gateway } = makeService();
      const alice = seedUserAndDevice(prisma, 'alice');
      const bob = seedUserAndDevice(prisma, 'bob');
      const conversationId = seedDirectConversation(
        prisma,
        alice.userId,
        bob.userId,
      );

      const sent = await service.send(
        { userId: alice.userId, deviceId: alice.deviceId },
        buildSendDto({
          conversationId,
          senderDeviceId: alice.deviceId,
          recipientUserId: bob.userId,
        }),
      );

      await service.markRead(
        { userId: bob.userId, deviceId: bob.deviceId },
        sent.message.id,
      );
      gateway.emitted.length = 0;

      await service.markRead(
        { userId: bob.userId, deviceId: bob.deviceId },
        sent.message.id,
      );

      expect(gateway.emitted).toHaveLength(0);
    });
  });

  describe('reactions', () => {
    it('addReaction upserts and emits', async () => {
      const { service, prisma, gateway } = makeService();
      const alice = seedUserAndDevice(prisma, 'alice');
      const bob = seedUserAndDevice(prisma, 'bob');
      const conversationId = seedDirectConversation(
        prisma,
        alice.userId,
        bob.userId,
      );

      const sent = await service.send(
        { userId: alice.userId, deviceId: alice.deviceId },
        buildSendDto({
          conversationId,
          senderDeviceId: alice.deviceId,
          recipientUserId: bob.userId,
        }),
      );
      gateway.emitted.length = 0;

      const reaction = await service.addReaction(
        { userId: bob.userId },
        sent.message.id,
        '👍',
      );

      expect(reaction.emoji).toBe('👍');
      const emittedAdd = gateway.emitted.find(
        (e) =>
          e.event === 'message.reaction' &&
          (e.payload as { action: string }).action === 'add',
      );
      expect(emittedAdd).toBeDefined();
    });

    it('removeReaction emits with action=remove', async () => {
      const { service, prisma, gateway } = makeService();
      const alice = seedUserAndDevice(prisma, 'alice');
      const bob = seedUserAndDevice(prisma, 'bob');
      const conversationId = seedDirectConversation(
        prisma,
        alice.userId,
        bob.userId,
      );

      const sent = await service.send(
        { userId: alice.userId, deviceId: alice.deviceId },
        buildSendDto({
          conversationId,
          senderDeviceId: alice.deviceId,
          recipientUserId: bob.userId,
        }),
      );
      await service.addReaction(
        { userId: bob.userId },
        sent.message.id,
        '❤️',
      );
      gateway.emitted.length = 0;

      await service.removeReaction({ userId: bob.userId }, sent.message.id);

      const emittedRemove = gateway.emitted.find(
        (e) =>
          e.event === 'message.reaction' &&
          (e.payload as { action: string }).action === 'remove',
      );
      expect(emittedRemove).toBeDefined();
    });

    it('rejects reactions from non-members', async () => {
      const { service, prisma } = makeService();
      const alice = seedUserAndDevice(prisma, 'alice');
      const bob = seedUserAndDevice(prisma, 'bob');
      const mallory = seedUserAndDevice(prisma, 'mallory');
      const conversationId = seedDirectConversation(
        prisma,
        alice.userId,
        bob.userId,
      );

      const sent = await service.send(
        { userId: alice.userId, deviceId: alice.deviceId },
        buildSendDto({
          conversationId,
          senderDeviceId: alice.deviceId,
          recipientUserId: bob.userId,
        }),
      );

      await expect(
        service.addReaction({ userId: mallory.userId }, sent.message.id, '👍'),
      ).rejects.toThrow('Message not found for actor');
    });
  });

  describe('deleteLocal', () => {
    it('acknowledges a delete for a member', async () => {
      const { service, prisma } = makeService();
      const alice = seedUserAndDevice(prisma, 'alice');
      const bob = seedUserAndDevice(prisma, 'bob');
      const conversationId = seedDirectConversation(
        prisma,
        alice.userId,
        bob.userId,
      );

      const sent = await service.send(
        { userId: alice.userId, deviceId: alice.deviceId },
        buildSendDto({
          conversationId,
          senderDeviceId: alice.deviceId,
          recipientUserId: bob.userId,
        }),
      );

      const result = await service.deleteLocal(
        { userId: bob.userId },
        sent.message.id,
      );
      expect(result.acknowledged).toBe(true);
      expect(result.messageId).toBe(sent.message.id);
    });

    it('rejects deleteLocal for non-members', async () => {
      const { service, prisma } = makeService();
      const alice = seedUserAndDevice(prisma, 'alice');
      const bob = seedUserAndDevice(prisma, 'bob');
      const mallory = seedUserAndDevice(prisma, 'mallory');
      const conversationId = seedDirectConversation(
        prisma,
        alice.userId,
        bob.userId,
      );

      const sent = await service.send(
        { userId: alice.userId, deviceId: alice.deviceId },
        buildSendDto({
          conversationId,
          senderDeviceId: alice.deviceId,
          recipientUserId: bob.userId,
        }),
      );

      await expect(
        service.deleteLocal({ userId: mallory.userId }, sent.message.id),
      ).rejects.toThrow('Message not found for actor');
    });
  });
});
