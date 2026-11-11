import { randomUUID } from 'node:crypto';

import { Test } from '@nestjs/testing';
import { Prisma } from '@prisma/client';

import { ConversationAccessService } from '../../common/conversation-access/conversation-access.service';
import { PrismaService } from '../../common/prisma.service';
import { FakePrismaService } from '../../../test/support/fake-prisma.service';
import { FakeRealtimeGateway, FakeSafetyService } from '../../../test/support/fake-services';
import { RealtimeGateway } from '../realtime/realtime.gateway';
import { SafetyService } from '../safety/safety.service';
import { CreateDirectConversationDto } from './dto/create-direct-conversation.dto';
import { ConversationsService } from './conversations.service';

function makeService() {
  const prisma = new FakePrismaService();
  const gateway = new FakeRealtimeGateway();
  const safety = new FakeSafetyService();
  const service = new ConversationsService(
    prisma as never,
    gateway as never,
    safety as never,
    new ConversationAccessService(prisma as never, safety as never),
  );
  return { prisma, gateway, safety, service };
}

function seedMessage(
  prisma: FakePrismaService,
  params: {
    conversationId: string;
    senderDeviceId: string;
    conversationOrder: number;
    expiresAt?: Date | null;
    serverReceivedAt?: Date;
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
    serverReceivedAt: params.serverReceivedAt ?? new Date(),
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

const minutesAgo = (minutes: number) => new Date(Date.now() - minutes * 60_000);

// A group where carol was added after the first message was sent.
function lateJoinerGroup() {
  const fixture = makeService();
  const alice = fixture.prisma.seedUser('alice');
  const carol = fixture.prisma.seedUser('carol');
  const conversationId = fixture.prisma.seedConversation('group', [
    { userId: alice.userId, role: 'owner', joinedAt: minutesAgo(30) },
    { userId: carol.userId, joinedAt: minutesAgo(10) },
  ]);
  const beforeJoin = seedMessage(fixture.prisma, {
    conversationId,
    senderDeviceId: alice.deviceId,
    conversationOrder: 1,
    serverReceivedAt: minutesAgo(20),
  });
  const afterJoin = seedMessage(fixture.prisma, {
    conversationId,
    senderDeviceId: alice.deviceId,
    conversationOrder: 2,
    serverReceivedAt: minutesAgo(5),
  });
  return { ...fixture, alice, carol, conversationId, beforeJoin, afterJoin };
}

describe('ConversationsService', () => {
  describe('createDirect', () => {
    it('creates a new direct conversation when none exists', async () => {
      const { service, prisma } = makeService();
      const alice = prisma.seedUser('alice');
      prisma.seedUser('bob');

      const { conversation } = await service.createDirect(alice.userId, buildDto('bob'));

      expect(conversation.type).toBe('direct');
      expect(conversation.members.map((m) => m.handle).sort()).toEqual(['alice', 'bob']);
      expect(prisma.conversations).toHaveLength(1);
    });

    it('returns the existing conversation when the pair already has one', async () => {
      const { service, prisma } = makeService();
      const alice = prisma.seedUser('alice');
      const bob = prisma.seedUser('bob');
      const existingId = prisma.seedConversation('direct', [alice.userId, bob.userId]);

      const { conversation } = await service.createDirect(alice.userId, buildDto('bob'));

      expect(conversation.id).toBe(existingId);
      expect(prisma.conversations).toHaveLength(1);
    });

    it('answers an unknown handle with handle_not_found', async () => {
      const { service, prisma } = makeService();
      const alice = prisma.seedUser('alice');

      await expect(service.createDirect(alice.userId, buildDto('ghost'))).rejects.toMatchObject({
        status: 404,
        response: { code: 'handle_not_found' },
      });
    });

    it('answers a blocked peer exactly like an unknown handle', async () => {
      const { service, prisma, safety } = makeService();
      const alice = prisma.seedUser('alice');
      const bob = prisma.seedUser('bob');
      safety.setBlocked(bob.userId, alice.userId);

      await expect(service.createDirect(alice.userId, buildDto('bob'))).rejects.toMatchObject({
        status: 404,
        response: { code: 'handle_not_found' },
      });
    });

    it('rejects a conversation with yourself', async () => {
      const { service, prisma } = makeService();
      const alice = prisma.seedUser('alice');

      await expect(service.createDirect(alice.userId, buildDto('alice'))).rejects.toMatchObject({
        status: 400,
        response: { code: 'cannot_add_self' },
      });
    });
  });

  describe('listForUser', () => {
    it('returns only conversations the user belongs to', async () => {
      const { service, prisma } = makeService();
      const alice = prisma.seedUser('alice');
      const bob = prisma.seedUser('bob');
      const carol = prisma.seedUser('carol');
      prisma.seedConversation('direct', [alice.userId, bob.userId]);
      prisma.seedConversation('direct', [bob.userId, carol.userId]);

      const result = await service.listForUser(alice.userId);

      expect(result).toHaveLength(1);
      expect(result[0]?.members.map((m) => m.handle).sort()).toEqual(['alice', 'bob']);
    });

    it('exposes Sender Keys metadata for groups only', async () => {
      const { service, prisma } = makeService();
      const alice = prisma.seedUser('alice');
      const bob = prisma.seedUser('bob');
      prisma.seedConversation('direct', [alice.userId, bob.userId]);
      prisma.seedConversation('group', [alice.userId, bob.userId], {
        groupUseSenderKeys: true,
        currentEpoch: 3,
      });

      const result = await service.listForUser(alice.userId);

      const direct = result.find((c) => c.type === 'direct');
      const group = result.find((c) => c.type === 'group');
      expect(direct).toBeDefined();
      expect(direct).not.toHaveProperty('useSenderKeys');
      expect(direct).not.toHaveProperty('currentEpoch');
      expect(group?.useSenderKeys).toBe(true);
      expect(group?.currentEpoch).toBe(3);
    });

    it('hides a pre-join lastMessage from a late group joiner', async () => {
      const fixture = makeService();
      const alice = fixture.prisma.seedUser('alice');
      const carol = fixture.prisma.seedUser('carol');
      const conversationId = fixture.prisma.seedConversation('group', [
        { userId: alice.userId, role: 'owner', joinedAt: minutesAgo(30) },
        { userId: carol.userId, joinedAt: minutesAgo(10) },
      ]);
      seedMessage(fixture.prisma, {
        conversationId,
        senderDeviceId: alice.deviceId,
        conversationOrder: 1,
        serverReceivedAt: minutesAgo(20),
      });

      const [forCarol] = await fixture.service.listForUser(carol.userId);
      const [forAlice] = await fixture.service.listForUser(alice.userId);

      expect(forCarol?.lastMessage).toBeNull();
      expect(forAlice?.lastMessage?.conversationOrder).toBe(1);
    });

    it('shows a channel subscriber only the owner, admins and themselves', async () => {
      const { service, prisma } = makeService();
      const owner = prisma.seedUser('owner');
      const admin = prisma.seedUser('admin');
      const subscriberA = prisma.seedUser('sub-a');
      const subscriberB = prisma.seedUser('sub-b');
      prisma.seedConversation('channel', [
        { userId: owner.userId, role: 'owner' },
        { userId: admin.userId, role: 'admin' },
        { userId: subscriberA.userId, role: 'subscriber' },
        { userId: subscriberB.userId, role: 'subscriber' },
      ]);

      const [forSubscriber] = await service.listForUser(subscriberA.userId);
      const [forAdmin] = await service.listForUser(admin.userId);

      expect(forSubscriber?.members.map((m) => m.handle).sort()).toEqual([
        'admin',
        'owner',
        'sub-a',
      ]);
      expect(forAdmin?.members).toHaveLength(4);
    });
  });

  describe('listMessagesForUser', () => {
    it('forbids non-members', async () => {
      const { service, prisma } = makeService();
      const alice = prisma.seedUser('alice');
      const bob = prisma.seedUser('bob');
      const carol = prisma.seedUser('carol');
      const conversationId = prisma.seedConversation('direct', [alice.userId, bob.userId]);

      await expect(
        service.listMessagesForUser(carol, conversationId, { limit: 50 }),
      ).rejects.toMatchObject({
        status: 403,
        response: { code: 'conversation_membership_required' },
      });
    });

    it('returns messages in ascending order and marks peer messages delivered', async () => {
      const { service, prisma, gateway } = makeService();
      const alice = prisma.seedUser('alice');
      const bob = prisma.seedUser('bob');
      const conversationId = prisma.seedConversation('direct', [alice.userId, bob.userId]);
      seedMessage(prisma, { conversationId, senderDeviceId: bob.deviceId, conversationOrder: 1 });
      seedMessage(prisma, { conversationId, senderDeviceId: alice.deviceId, conversationOrder: 2 });

      const result = await service.listMessagesForUser(alice, conversationId, { limit: 50 });

      expect(result.items.map((m) => m.conversationOrder)).toEqual([1, 2]);
      const deliveredEvents = gateway.emitted.filter((e) => e.event === 'message.delivered');
      expect(deliveredEvents.map((e) => e.userId).sort()).toEqual(
        [alice.userId, bob.userId].sort(),
      );
      expect(prisma.messageReceipts).toHaveLength(1);
      expect(prisma.messageReceipts[0]?.userId).toBe(alice.userId);
      expect(result.items[0]?.deliveredAt).not.toBeNull();
      const state = prisma.deviceConversationStates.find(
        (s) => s.deviceId === alice.deviceId && s.conversationId === conversationId,
      );
      expect(state?.lastSyncedConversationOrder).toBe(2);
    });

    // Prisma stamps an @updatedAt column on every upsert, so any timestamp on
    // this table would record when each device last opened every conversation.
    it('keeps the sync cursor as orders only, with no timestamp of when it moved', async () => {
      const cursorModel = Prisma.dmmf.datamodel.models.find(
        (model) => model.name === 'DeviceConversationState',
      );
      expect(cursorModel).toBeDefined();
      expect(
        cursorModel!.fields
          .filter((field) => field.type === 'DateTime' || field.isUpdatedAt)
          .map((field) => field.name),
      ).toEqual([]);

      const { service, prisma } = makeService();
      const alice = prisma.seedUser('alice');
      const bob = prisma.seedUser('bob');
      const conversationId = prisma.seedConversation('direct', [alice.userId, bob.userId]);
      seedMessage(prisma, { conversationId, senderDeviceId: bob.deviceId, conversationOrder: 1 });

      await service.listMessagesForUser(alice, conversationId, { limit: 50 });

      expect(Object.keys(prisma.deviceConversationStates[0]!).sort()).toEqual(
        [
          'conversationId',
          'deviceId',
          'id',
          'lastReadConversationOrder',
          'lastSyncedConversationOrder',
        ].sort(),
      );
    });

    it('does not mark delivered for messages the viewer sent', async () => {
      const { service, prisma, gateway } = makeService();
      const alice = prisma.seedUser('alice');
      const bob = prisma.seedUser('bob');
      const conversationId = prisma.seedConversation('direct', [alice.userId, bob.userId]);
      seedMessage(prisma, { conversationId, senderDeviceId: alice.deviceId, conversationOrder: 1 });

      await service.listMessagesForUser(alice, conversationId, { limit: 50 });

      expect(prisma.messageReceipts).toHaveLength(0);
      expect(gateway.emitted.filter((e) => e.event === 'message.delivered')).toHaveLength(0);
    });

    it('delivered receipts do not reach a blocked direct peer', async () => {
      const { service, prisma, gateway, safety } = makeService();
      const alice = prisma.seedUser('alice');
      const bob = prisma.seedUser('bob');
      const conversationId = prisma.seedConversation('direct', [alice.userId, bob.userId]);
      seedMessage(prisma, { conversationId, senderDeviceId: bob.deviceId, conversationOrder: 1 });
      safety.setBlocked(alice.userId, bob.userId);

      await service.listMessagesForUser(alice, conversationId, { limit: 50 });

      expect(gateway.emitted.map((e) => [e.userId, e.event])).toEqual([
        [alice.userId, 'message.delivered'],
      ]);
      expect(prisma.messageReceipts).toEqual([
        expect.objectContaining({ userId: alice.userId, deliveredAt: expect.any(Date) }),
      ]);
    });

    it('excludes expired messages from the returned list', async () => {
      const { service, prisma } = makeService();
      const alice = prisma.seedUser('alice');
      const bob = prisma.seedUser('bob');
      const conversationId = prisma.seedConversation('direct', [alice.userId, bob.userId]);
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

      const result = await service.listMessagesForUser(alice, conversationId, { limit: 50 });

      expect(result.items.map((item) => item.id)).toEqual([freshId]);
    });

    it('answers an unknown cursor with message_not_found', async () => {
      const { service, prisma } = makeService();
      const alice = prisma.seedUser('alice');
      const bob = prisma.seedUser('bob');
      const conversationId = prisma.seedConversation('direct', [alice.userId, bob.userId]);

      for (const cursor of ['nonexistent-id', randomUUID()]) {
        await expect(
          service.listMessagesForUser(alice, conversationId, { limit: 50, cursor }),
        ).rejects.toMatchObject({ status: 404, response: { code: 'message_not_found' } });
      }
    });

    it('rejects a malformed conversation id before touching the database', async () => {
      const { service, prisma } = makeService();
      const alice = prisma.seedUser('alice');
      const findUnique = jest.spyOn(prisma.conversationMember, 'findUnique');

      await expect(
        service.listMessagesForUser(alice, 'conv-1', { limit: 50 }),
      ).rejects.toMatchObject({ status: 400, response: { code: 'validation_failed' } });
      expect(findUnique).not.toHaveBeenCalled();
    });

    it('group member added after m1 lists only later messages', async () => {
      const { service, carol, conversationId, afterJoin } = lateJoinerGroup();

      const result = await service.listMessagesForUser(carol, conversationId, { limit: 50 });

      expect(result.items.map((item) => item.id)).toEqual([afterJoin]);
    });

    it('no delivered receipts for pre-join messages', async () => {
      const { service, prisma, gateway, carol, conversationId, beforeJoin, afterJoin } =
        lateJoinerGroup();

      await service.listMessagesForUser(carol, conversationId, { limit: 50 });

      expect(prisma.messageReceipts.map((receipt) => receipt.messageId)).toEqual([afterJoin]);
      const delivered = gateway.emitted.filter((e) => e.event === 'message.delivered');
      expect(
        delivered.every((e) => (e.payload as { messageId: string }).messageId !== beforeJoin),
      ).toBe(true);
    });

    it('lets channel subscribers read the full backlog without receipts', async () => {
      const { service, prisma, gateway } = makeService();
      const owner = prisma.seedUser('owner');
      const subscriber = prisma.seedUser('subscriber');
      const conversationId = prisma.seedConversation('channel', [
        { userId: owner.userId, role: 'owner', joinedAt: minutesAgo(30) },
        { userId: subscriber.userId, role: 'subscriber', joinedAt: minutesAgo(5) },
      ]);
      seedMessage(prisma, {
        conversationId,
        senderDeviceId: owner.deviceId,
        conversationOrder: 1,
        serverReceivedAt: minutesAgo(20),
      });

      const result = await service.listMessagesForUser(subscriber, conversationId, { limit: 50 });

      expect(result.items).toHaveLength(1);
      expect(prisma.messageReceipts).toHaveLength(0);
      expect(gateway.emitted).toHaveLength(0);
    });
  });

  describe('setDisappearingTimer', () => {
    it('updates the timer and notifies every member', async () => {
      const { service, prisma, gateway } = makeService();
      const alice = prisma.seedUser('alice');
      const bob = prisma.seedUser('bob');
      const conversationId = prisma.seedConversation('direct', [alice.userId, bob.userId]);

      const { conversation } = await service.setDisappearingTimer(
        alice.userId,
        conversationId,
        3600,
      );

      expect(conversation.disappearingTimerSeconds).toBe(3600);
      expect(
        gateway.emitted
          .filter((e) => e.event === 'conversation.timer.changed')
          .map((e) => e.userId)
          .sort(),
      ).toEqual([alice.userId, bob.userId].sort());
    });

    it('subscriber timer change 403', async () => {
      const { service, prisma } = makeService();
      const owner = prisma.seedUser('owner');
      const subscriber = prisma.seedUser('subscriber');
      const conversationId = prisma.seedConversation('channel', [
        { userId: owner.userId, role: 'owner' },
        { userId: subscriber.userId, role: 'subscriber' },
      ]);

      await expect(
        service.setDisappearingTimer(subscriber.userId, conversationId, 60),
      ).rejects.toMatchObject({ status: 403, response: { code: 'conversation_role_required' } });
      expect(prisma.conversations[0]?.disappearingTimerSeconds).toBeNull();
    });
  });

  describe('lifecycle', () => {
    afterEach(() => {
      jest.useRealTimers();
    });

    it('module init schedules no sweep timer', async () => {
      jest.useFakeTimers();
      const { prisma, gateway, safety } = makeService();
      // A real Nest module runs every lifecycle hook the provider declares,
      // so a sweep re-added under any hook name is caught.
      const moduleRef = await Test.createTestingModule({
        providers: [
          ConversationsService,
          { provide: PrismaService, useValue: prisma },
          { provide: RealtimeGateway, useValue: gateway },
          { provide: SafetyService, useValue: safety },
          {
            provide: ConversationAccessService,
            useValue: new ConversationAccessService(prisma as never, safety as never),
          },
        ],
      }).compile();

      await moduleRef.init();

      expect(jest.getTimerCount()).toBe(0);
      await moduleRef.close();
    });
  });
});
