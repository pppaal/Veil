import {
  NoopPushProvider,
  PushService,
} from '../../src/modules/push/push.service';
import { ApnsMetadataPushProvider } from '../../src/modules/push/apns-push.provider';
import { FcmMetadataPushProvider } from '../../src/modules/push/fcm-push.provider';

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

  it('builds metadata-only APNs requests without plaintext body fields', async () => {
    const provider = new ApnsMetadataPushProvider({
      apnsBundleId: 'io.veil.mobile',
      apnsTeamId: 'TEAMID123',
      apnsKeyId: 'KEYID123',
      apnsPrivateKeyPem: '-----BEGIN PRIVATE KEY-----mock-----END PRIVATE KEY-----',
      apnsUseSandbox: true,
    } as never);
    const service = new PushService(provider);
    const request = provider.buildRequest('push-token', hint);

    expect(service.providerKind).toBe('apns');
    expect(request.endpoint).toContain('api.sandbox.push.apple.com/3/device/push-token');
    expect(request.headers['apns-topic']).toBe('io.veil.mobile');
    expect(request.body.aps['content-available']).toBe(1);
    expect(request.body.veil).toEqual(hint);
    await expect(service.sendMessageHint('push-token', hint)).resolves.toBeUndefined();
  });

  it('builds metadata-only FCM requests without plaintext body fields', async () => {
    const provider = new FcmMetadataPushProvider({
      fcmProjectId: 'veil-beta',
      fcmServiceAccountJson: '{"type":"service_account"}',
    } as never);
    const service = new PushService(provider);
    const request = provider.buildRequest('push-token', hint);

    expect(service.providerKind).toBe('fcm');
    expect(request.endpoint).toContain('/projects/veil-beta/messages:send');
    expect(request.body.message.token).toBe('push-token');
    expect(request.body.message.data).toEqual({
      kind: hint.kind,
      messageId: hint.messageId,
      conversationId: hint.conversationId,
      senderDeviceId: hint.senderDeviceId,
      serverReceivedAt: hint.serverReceivedAt,
    });
    await expect(service.sendMessageHint('push-token', hint)).resolves.toBeUndefined();
  });
});
