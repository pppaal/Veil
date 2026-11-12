import { randomUUID } from 'node:crypto';

import { ConversationAccessService } from '../../common/conversation-access/conversation-access.service';
import { FakePrismaService } from '../../../test/support/fake-prisma.service';
import { FakeRealtimeGateway, FakeSafetyService } from '../../../test/support/fake-services';
import { ChannelsService } from './channels.service';

function channelFixture(options: { isPublic?: boolean } = {}) {
  const prisma = new FakePrismaService();
  const gateway = new FakeRealtimeGateway();
  const service = new ChannelsService(
    prisma as never,
    gateway as never,
    new ConversationAccessService(prisma as never, new FakeSafetyService() as never),
  );
  const owner = prisma.seedUser('owner');
  const admin = prisma.seedUser('admin');
  const subscriber = prisma.seedUser('subscriber');
  const outsider = prisma.seedUser('outsider');
  const channelId = prisma.seedConversation(
    'channel',
    [
      { userId: owner.userId, role: 'owner' },
      { userId: admin.userId, role: 'admin' },
      { userId: subscriber.userId, role: 'subscriber' },
    ],
    { isPublic: options.isPublic ?? true },
  );
  prisma.messages.push({
    id: randomUUID(),
    conversationId: channelId,
    senderDeviceId: owner.deviceId,
    clientMessageId: 'client-post-1',
    conversationOrder: 1,
    ciphertext: 'post-ciphertext',
    nonce: 'post-nonce',
    messageType: 'text',
    attachmentId: null,
    attachmentRef: null,
    serverReceivedAt: new Date(),
    deletedAt: null,
    expiresAt: null,
  });
  const as = (user: { userId: string; deviceId: string }, handle: string) => ({ ...user, handle });
  return { prisma, gateway, service, owner, admin, subscriber, outsider, channelId, as };
}

describe('ChannelsService', () => {
  describe('getChannel', () => {
    it('non-member sees subscriberCount and admins only', async () => {
      const { service, outsider, channelId, as } = channelFixture();

      const channel = await service.getChannel(as(outsider, 'outsider'), channelId);

      expect(channel.subscriberCount).toBe(3);
      expect(channel.admins.map((a) => a.handle).sort()).toEqual(['admin', 'owner']);
      expect(channel.viewerRole).toBeNull();
      expect(channel).not.toHaveProperty('members');
    });

    it('admin sees members', async () => {
      const { service, admin, channelId, as } = channelFixture();

      const channel = await service.getChannel(as(admin, 'admin'), channelId);

      expect(channel.viewerRole).toBe('admin');
      expect(channel.members?.map((m) => [m.handle, m.role]).sort()).toEqual([
        ['admin', 'admin'],
        ['owner', 'owner'],
        ['subscriber', 'subscriber'],
      ]);
    });

    it('subscribers see the latest post but not each other', async () => {
      const { service, subscriber, channelId, as } = channelFixture();

      const channel = await service.getChannel(as(subscriber, 'subscriber'), channelId);

      expect(channel.viewerRole).toBe('subscriber');
      expect(channel).not.toHaveProperty('members');
      expect(channel.lastMessage?.ciphertext).toBe('post-ciphertext');
    });

    it('non-member never receives lastMessage', async () => {
      const { service, outsider, channelId, as } = channelFixture();

      const channel = await service.getChannel(as(outsider, 'outsider'), channelId);

      expect(channel).not.toHaveProperty('lastMessage');
      expect(JSON.stringify(channel)).not.toContain('post-ciphertext');
    });

    it('answers a private channel to a non-member exactly like a missing one', async () => {
      const { service, outsider, channelId, as } = channelFixture({ isPublic: false });

      for (const id of [channelId, randomUUID()]) {
        await expect(service.getChannel(as(outsider, 'outsider'), id)).rejects.toMatchObject({
          status: 404,
          response: { code: 'channel_not_found' },
        });
      }
    });
  });

  describe('membership', () => {
    it('subscribes to a public channel idempotently and notifies only the subscriber', async () => {
      const { service, prisma, gateway, outsider, channelId, as } = channelFixture();

      await service.subscribe(as(outsider, 'outsider'), channelId);
      await service.subscribe(as(outsider, 'outsider'), channelId);

      const memberships = prisma.conversationMembers.filter((m) => m.userId === outsider.userId);
      expect(memberships.map((m) => m.role)).toEqual(['subscriber']);
      expect(gateway.emitted.map((e) => e.userId)).toEqual([outsider.userId]);
    });

    it('refuses to subscribe to a private channel', async () => {
      const { service, outsider, channelId, as } = channelFixture({ isPublic: false });

      await expect(service.subscribe(as(outsider, 'outsider'), channelId)).rejects.toMatchObject({
        status: 404,
        response: { code: 'channel_not_found' },
      });
    });

    it('unsubscribing tells only the leaver and the channel staff', async () => {
      const { service, gateway, owner, admin, subscriber, channelId, as } = channelFixture();

      await service.unsubscribe(as(subscriber, 'subscriber'), channelId);

      expect(gateway.emitted.map((e) => e.userId).sort()).toEqual(
        [owner.userId, admin.userId, subscriber.userId].sort(),
      );
    });

    it('an unsubscribed member leaves no sync cursor or mute behind in that channel', async () => {
      const { prisma, service, admin, subscriber, channelId, as } = channelFixture();
      prisma.deviceConversationStates.push(
        {
          id: randomUUID(),
          deviceId: subscriber.deviceId,
          conversationId: channelId,
          lastSyncedConversationOrder: 1,
          lastReadConversationOrder: 1,
        },
        {
          id: randomUUID(),
          deviceId: admin.deviceId,
          conversationId: channelId,
          lastSyncedConversationOrder: 1,
          lastReadConversationOrder: 1,
        },
      );
      prisma.conversationMutes.push(
        {
          userId: subscriber.userId,
          conversationId: channelId,
          mutedUntil: null,
          createdAt: new Date(),
        },
        {
          userId: admin.userId,
          conversationId: channelId,
          mutedUntil: null,
          createdAt: new Date(),
        },
      );

      await service.unsubscribe(as(subscriber, 'subscriber'), channelId);

      expect(prisma.deviceConversationStates.map((state) => state.deviceId)).toEqual([
        admin.deviceId,
      ]);
      expect(prisma.conversationMutes.map((mute) => mute.userId)).toEqual([admin.userId]);
    });

    it('the owner cannot unsubscribe', async () => {
      const { service, owner, channelId, as } = channelFixture();

      await expect(service.unsubscribe(as(owner, 'owner'), channelId)).rejects.toMatchObject({
        status: 409,
        response: { code: 'owner_immutable' },
      });
    });
  });

  describe('updateChannel', () => {
    it('lets channel staff edit the metadata', async () => {
      const { service, admin, channelId, as } = channelFixture();

      const updated = await service.updateChannel(as(admin, 'admin'), channelId, { name: 'News' });

      expect(updated.name).toBe('News');
    });

    it('refuses subscribers', async () => {
      const { service, subscriber, channelId, as } = channelFixture();

      await expect(
        service.updateChannel(as(subscriber, 'subscriber'), channelId, { name: 'Mine now' }),
      ).rejects.toMatchObject({ status: 403, response: { code: 'conversation_role_required' } });
    });
  });
});
