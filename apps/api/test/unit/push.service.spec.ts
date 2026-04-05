import {
  MetadataOnlySeamPushProvider,
  NoopPushProvider,
  PushService,
} from '../../src/modules/push/push.service';

describe('PushService', () => {
  const hint = {
    kind: 'message.new' as const,
    messageId: 'msg-1',
    conversationId: 'conv-1',
    senderDeviceId: 'device-a',
    serverReceivedAt: new Date().toISOString(),
  };

  it('reports none when the noop provider is active', async () => {
    const service = new PushService(new NoopPushProvider());

    expect(service.providerKind).toBe('none');
    await expect(service.sendMessageHint('push-token', hint)).resolves.toBeUndefined();
  });

  it('preserves explicit provider kind for metadata-only seams', async () => {
    const service = new PushService(new MetadataOnlySeamPushProvider('apns'));

    expect(service.providerKind).toBe('apns');
    await expect(service.sendMessageHint('push-token', hint)).resolves.toBeUndefined();
  });
});
