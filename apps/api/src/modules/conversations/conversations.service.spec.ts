import { ForbiddenException, NotFoundException } from '@nestjs/common';
import { randomUUID } from 'node:crypto';

import { ConversationsService } from './conversations.service';
import { FakePrismaService } from '../../../test/support/fake-prisma.service';
import {
  FakeAttachmentStorageGateway,
  FakeRealtimeGateway,
} from '../../../test/support/fake-services';
import { CreateDirectConversationDto } from './dto/create-direct-conversation.dto';

type Seed = {
  prisma: FakePrismaService;
  gateway: FakeRealtimeGateway;
  storage: FakeAttachmentStorageGateway;
  service: ConversationsService;
};

function makeService(): Seed {
  const prisma = new FakePrismaService();
  const gateway = new FakeRealtimeGateway();
  const storage = new FakeAttachmentStorageGateway();
  const service = new ConversationsService(
    prisma as never,
    gateway as never,
    storage as never,
  );
  return { prisma, gateway, storage, service };
}

function seedUser(prisma: FakePrismaService, handle: string): { userId: string; deviceId: string } {
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
    publicIdentityKey: 'pub',
    signedPrekeyBundle: 'prekey',
    authPublicKey: 'auth',
    pushToken: null,
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

function seedDirect(prisma: FakePrismaService, a: string, b: string): string {
  const conversationId = randomUUID();
  prisma.conversations.push({ id: conversationId, type: 'direct', createdAt: new Date() });
  prisma.conversationMembers.push({ id: randomUUID(), conversationId, userId: a, joinedAt: new Date() });
  prisma.conversationMembers.push({ id: randomUUID(), conversationId, userId: b, joinedAt: new Date() });
  return conversationId;
}

function seedMessage(
  prisma: FakePrismaService,
  params: {
    conversationId: string;
    senderDeviceId: string;
    conversationOrder: number;
    expiresAt?: Date | null;
  },
): string {
  const id = randomUUID();
  prisma.messages.push({
    id,
    conversationId: params.conversationId,
    senderDeviceId: params.senderDeviceId,
    clientMessageId: `c-${id.slice(0, 8)}`,
    conversationOrder: params.conversationOrder,
    ciphertext: 'ct',
    nonce: 'nn',
    messageType: 'text',
    attachmentId: null,
    attachmentRef: null,
    serverReceivedAt: new Date(),
    deletedAt: null,
    expiresAt: params.expiresAt ?? null,
  });
  return id;
}

function buildDto(peerHandle: string): CreateDirectConversationDto {
  const dto = new CreateDirectConversationDto();
  dto.peerHandle = peerHandle;
  return dto;
}

describe('ConversationsService', () => {
  describe('createDirect', () => {
    it('creates a new direct conversation when none exists', async () => {
      const { service, prisma } = makeService();
      const alice = seedUser(prisma, 'alice');
      const bob = seedUser(prisma, 'bob');

      const { conversation } = await service.createDirect(alice.userId, buildDto('bob'));

      expect(conversation.type).toBe('direct');
      expect(conversation.members.map((m) => m.handle).sort()).toEqual(['alice', 'bob']);
      expect(prisma.conversations).toHaveLength(1);
    });

    it('returns the existing conversation when the pair already has one', async () => {
      const { service, prisma } = makeService();
      const alice = seedUser(prisma, 'alice');
      const bob = seedUser(prisma, 'bob');
      const existingId = seedDirect(prisma, alice.userId, bob.userId);

      const { conversation } = await service.createDirect(alice.userId, buildDto('bob'));

      expect(conversation.id).toBe(existingId);
      expect(prisma.conversations).toHaveLength(1);
    });

    it('throws NotFoundException when peer handle is unknown', async () => {
      const { service, prisma } = makeService();
      const alice = seedUser(prisma, 'alice');

      await expect(
        service.createDirect(alice.userId, buildDto('ghost')),
      ).rejects.toBeInstanceOf(NotFoundException);
    });

    it('throws ForbiddenException when peer is the caller', async () => {
      const { service, prisma } = makeService();
      const alice = seedUser(prisma, 'alice');

      await expect(
        service.createDirect(alice.userId, buildDto('alice')),
      ).rejects.toBeInstanceOf(ForbiddenException);
    });
  });

  describe('listForUser', () => {
    it('returns only conversations the user belongs to', async () => {
      const { service, prisma } = makeService();
      const alice = seedUser(prisma, 'alice');
      const bob = seedUser(prisma, 'bob');
      const carol = seedUser(prisma, 'carol');
      seedDirect(prisma, alice.userId, bob.userId);
      seedDirect(prisma, bob.userId, carol.userId);

      const result = await service.listForUser(alice.userId);

      expect(result).toHaveLength(1);
      expect(result[0]?.members.map((m) => m.handle).sort()).toEqual(['alice', 'bob']);
    });
  });

  describe('listMessagesForUser', () => {
    it('forbids non-members', async () => {
      const { service, prisma } = makeService();
      const alice = seedUser(prisma, 'alice');
      const bob = seedUser(prisma, 'bob');
      const carol = seedUser(prisma, 'carol');
      const conversationId = seedDirect(prisma, alice.userId, bob.userId);

      await expect(
        service.listMessagesForUser(
          { userId: carol.userId, deviceId: carol.deviceId },
          conversationId,
          { limit: 50 },
        ),
      ).rejects.toBeInstanceOf(ForbiddenException);
    });

    it('returns messages in ascending order and emits delivered events for peer messages', async () => {
      const { service, prisma, gateway } = makeService();
      const alice = seedUser(prisma, 'alice');
      const bob = seedUser(prisma, 'bob');
      const conversationId = seedDirect(prisma, alice.userId, bob.userId);
      seedMessage(prisma, {
        conversationId,
        senderDeviceId: bob.deviceId,
        conversationOrder: 1,
      });
      seedMessage(prisma, {
        conversationId,
        senderDeviceId: alice.deviceId,
        conversationOrder: 2,
      });

      const result = await service.listMessagesForUser(
        { userId: alice.userId, deviceId: alice.deviceId },
        conversationId,
        { limit: 50 },
      );

      expect(result.items.map((m) => m.conversationOrder)).toEqual([1, 2]);
      const deliveredEvents = gateway.emitted.filter((e) => e.event === 'message.delivered');
      expect(deliveredEvents).toHaveLength(2);
      expect(prisma.messageReceipts).toHaveLength(1);
      expect(prisma.messageReceipts[0]?.userId).toBe(alice.userId);
      const state = prisma.deviceConversationStates.find(
        (s) => s.deviceId === alice.deviceId && s.conversationId === conversationId,
      );
      expect(state?.lastSyncedConversationOrder).toBe(2);
    });

    it('does not mark delivered for messages the viewer sent', async () => {
      const { service, prisma, gateway } = makeService();
      const alice = seedUser(prisma, 'alice');
      const bob = seedUser(prisma, 'bob');
      const conversationId = seedDirect(prisma, alice.userId, bob.userId);
      seedMessage(prisma, {
        conversationId,
        senderDeviceId: alice.deviceId,
        conversationOrder: 1,
      });

      await service.listMessagesForUser(
        { userId: alice.userId, deviceId: alice.deviceId },
        conversationId,
        { limit: 50 },
      );

      expect(prisma.messageReceipts).toHaveLength(0);
      expect(gateway.emitted.filter((e) => e.event === 'message.delivered')).toHaveLength(0);
    });

    it('excludes expired messages from the returned list', async () => {
      const { service, prisma } = makeService();
      const alice = seedUser(prisma, 'alice');
      const bob = seedUser(prisma, 'bob');
      const conversationId = seedDirect(prisma, alice.userId, bob.userId);
      seedMessage(prisma, {
        conversationId,
        senderDeviceId: bob.deviceId,
        conversationOrder: 1,
        expiresAt: new Date(Date.now() - 60_000),
      });
      const freshId = seedMessage(prisma, {
        conversationId,
        senderDeviceId: bob.deviceId,
        conversationOrder: 2,
      });

      const result = await service.listMessagesForUser(
        { userId: alice.userId, deviceId: alice.deviceId },
        conversationId,
        { limit: 50 },
      );

      expect(result.items).toHaveLength(1);
      expect(result.items[0]?.id).toBe(freshId);
    });

    it('throws NotFoundException when cursor refers to unknown message', async () => {
      const { service, prisma } = makeService();
      const alice = seedUser(prisma, 'alice');
      const bob = seedUser(prisma, 'bob');
      const conversationId = seedDirect(prisma, alice.userId, bob.userId);

      await expect(
        service.listMessagesForUser(
          { userId: alice.userId, deviceId: alice.deviceId },
          conversationId,
          { limit: 50, cursor: 'nonexistent-id' },
        ),
      ).rejects.toBeInstanceOf(NotFoundException);
    });
  });
});
