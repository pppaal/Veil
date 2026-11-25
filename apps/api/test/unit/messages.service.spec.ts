import { ConversationAccessService } from '../../src/common/conversation-access/conversation-access.service';
import { MessagesService } from '../../src/modules/messages/messages.service';
import { FakePrismaService } from '../support/fake-prisma.service';
import { AppLoggerService } from '../../src/common/logger/app-logger.service';
import {
  FakePushService,
  FakeRealtimeGateway,
  FakeSafetyService,
  settleDetachedWork,
} from '../support/fake-services';

describe('MessagesService', () => {
  function createFixture() {
    const prisma = new FakePrismaService();
    const realtime = new FakeRealtimeGateway();
    const push = new FakePushService();
    const safety = new FakeSafetyService();
    const metrics = { messagesSentTotal: { inc: () => undefined } };
    const service = new MessagesService(
      prisma as never,
      push as never,
      realtime as never,
      safety as never,
      metrics as never,
      new ConversationAccessService(prisma as never, safety as never),
      { isProduction: false } as never,
      new AppLoggerService(),
    );

    const atlas = prisma.seedUser('atlas', { pushToken: 'push-a' });
    const selene = prisma.seedUser('selene', { pushToken: 'push-b' });
    const conversationId = prisma.seedConversation('direct', [atlas.userId, selene.userId]);

    const dto = {
      conversationId,
      clientMessageId: 'client-msg-0001',
      envelope: {
        version: 'veil-envelope-v1-dev',
        conversationId,
        senderDeviceId: atlas.deviceId,
        recipientUserId: selene.userId,
        ciphertext: 'opaque-ciphertext',
        nonce: 'nonce-1',
        messageType: 'text' as const,
      },
    };

    return { prisma, realtime, push, service, atlas, selene, dto };
  }

  it('deduplicates idempotent sends from the same device', async () => {
    const { prisma, service, push, atlas, dto } = createFixture();

    const first = await service.send(atlas, dto as never);
    const second = await service.send(atlas, dto as never);
    await settleDetachedWork();

    expect(first.idempotent).toBe(false);
    expect(second.idempotent).toBe(true);
    expect(second.message.id).toBe(first.message.id);
    expect(prisma.messages).toHaveLength(1);
    expect(push.sentHints).toHaveLength(1);
  });

  it('sends opaque wake-only push fallback when the recipient has no active socket', async () => {
    const { push, service, atlas, dto } = createFixture();

    await service.send(atlas, dto as never);
    await settleDetachedWork();

    expect(push.sentHints).toHaveLength(1);
    expect(push.sentHints[0]).toEqual({
      pushToken: 'push-b',
      hint: { kind: 'wake' },
    });
    const serialized = JSON.stringify(push.sentHints[0]!.hint);
    expect(serialized).not.toContain('conversationId');
    expect(serialized).not.toContain('messageId');
    expect(serialized).not.toContain('opaque-ciphertext');
    expect(serialized).not.toContain('senderDeviceId');
  });

  it('skips push fallback when the recipient already has an active socket', async () => {
    const { realtime, push, service, atlas, selene, dto } = createFixture();
    realtime.connectedUsers.add(selene.userId);
    realtime.connectedDevices.add(selene.deviceId);

    await service.send(atlas, dto as never);
    await settleDetachedWork();

    expect(push.sentHints).toHaveLength(0);
  });
});
