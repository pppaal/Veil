import { MessagesService } from '../../src/modules/messages/messages.service';
import { FakePrismaService } from '../support/fake-prisma.service';
import { FakePushService, FakeRealtimeGateway } from '../support/fake-services';

describe('MessagesService', () => {
  function createFixture() {
    const prisma = new FakePrismaService();
    const realtime = new FakeRealtimeGateway();
    const push = new FakePushService();
    const service = new MessagesService(
      prisma as never,
      push as never,
      realtime as never,
    );

    prisma.users.push(
      {
        id: 'user-a',
        handle: 'atlas',
        displayName: 'Atlas',
        avatarPath: null,
        status: 'active',
        activeDeviceId: 'device-a',
        createdAt: new Date(),
        updatedAt: new Date(),
      },
      {
        id: 'user-b',
        handle: 'selene',
        displayName: 'Selene',
        avatarPath: null,
        status: 'active',
        activeDeviceId: 'device-b',
        createdAt: new Date(),
        updatedAt: new Date(),
      },
    );

    prisma.devices.push(
      {
        id: 'device-a',
        userId: 'user-a',
        platform: 'android',
        deviceName: 'Pixel',
        publicIdentityKey: 'pub-a',
        signedPrekeyBundle: 'prekey-a',
        authPublicKey: 'auth-a',
        pushToken: 'push-a',
        isActive: true,
        revokedAt: null,
        createdAt: new Date(),
        lastSeenAt: new Date(),
      },
      {
        id: 'device-b',
        userId: 'user-b',
        platform: 'ios',
        deviceName: 'iPhone',
        publicIdentityKey: 'pub-b',
        signedPrekeyBundle: 'prekey-b',
        authPublicKey: 'auth-b',
        pushToken: 'push-b',
        isActive: true,
        revokedAt: null,
        createdAt: new Date(),
        lastSeenAt: new Date(),
      },
    );

    prisma.conversations.push({
      id: 'conv-1',
      type: 'direct',
      createdAt: new Date(),
    });
    prisma.conversationMembers.push(
      {
        id: 'member-a',
        conversationId: 'conv-1',
        userId: 'user-a',
        joinedAt: new Date(),
      },
      {
        id: 'member-b',
        conversationId: 'conv-1',
        userId: 'user-b',
        joinedAt: new Date(),
      },
    );

    return { prisma, realtime, push, service };
  }

  const dto = {
    conversationId: 'conv-1',
    clientMessageId: 'client-msg-0001',
    envelope: {
      version: 'veil-envelope-v1-dev',
      conversationId: 'conv-1',
      senderDeviceId: 'device-a',
      recipientUserId: 'user-b',
      ciphertext: 'opaque-ciphertext',
      nonce: 'nonce-1',
      messageType: 'text' as const,
    },
  };

  it('deduplicates idempotent sends from the same device', async () => {
    const { prisma, service, push } = createFixture();

    const first = await service.send(
      { userId: 'user-a', deviceId: 'device-a' },
      dto as never,
    );
    const second = await service.send(
      { userId: 'user-a', deviceId: 'device-a' },
      dto as never,
    );

    expect(first.idempotent).toBe(false);
    expect(second.idempotent).toBe(true);
    expect(second.message.id).toBe(first.message.id);
    expect(prisma.messages).toHaveLength(1);
    expect(push.sentHints).toHaveLength(1);
  });

  it('sends metadata-only push fallback when the recipient has no active socket', async () => {
    const { push, service } = createFixture();

    await service.send({ userId: 'user-a', deviceId: 'device-a' }, dto as never);

    expect(push.sentHints).toHaveLength(1);
    expect(push.sentHints[0]).toEqual({
      pushToken: 'push-b',
      hint: expect.objectContaining({
        kind: 'message.new',
        conversationId: 'conv-1',
        senderDeviceId: 'device-a',
      }),
    });
    expect(JSON.stringify(push.sentHints[0]!.hint)).not.toContain('opaque-ciphertext');
  });

  it('skips push fallback when the recipient already has an active socket', async () => {
    const { realtime, push, service } = createFixture();
    realtime.connectedUsers.add('user-b');

    await service.send({ userId: 'user-a', deviceId: 'device-a' }, dto as never);

    expect(push.sentHints).toHaveLength(0);
  });
});
