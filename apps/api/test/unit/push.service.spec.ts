import { generateKeyPairSync } from 'node:crypto';

import { NoopPushProvider, PushService } from '../../src/modules/push/push.service';
import { ApnsMetadataPushProvider } from '../../src/modules/push/apns-push.provider';
import { FcmMetadataPushProvider } from '../../src/modules/push/fcm-push.provider';

describe('PushService', () => {
  const hint = {
    kind: 'wake' as const,
  };
  const fakeLogger = { info() {}, warn() {}, error() {} } as never;
  const fakeMetrics = { pushDeliveryTotal: { inc() {} } } as never;

  it('reports none when the noop provider is active', async () => {
    const service = new PushService(new NoopPushProvider(), fakeLogger, fakeMetrics);

    expect(service.providerKind).toBe('none');
    await expect(service.sendMessageHint('push-token', hint)).resolves.toBeUndefined();
  });

  it('builds opaque wake-only APNs requests with no conversation metadata', async () => {
    const provider = new ApnsMetadataPushProvider({
      apnsBundleId: 'io.veil.mobile',
      apnsTeamId: 'TEAMID123',
      apnsKeyId: 'KEYID123',
      apnsPrivateKeyPem: '-----BEGIN PRIVATE KEY-----mock-----END PRIVATE KEY-----',
      apnsUseSandbox: true,
    } as never);
    const service = new PushService(provider, fakeLogger, fakeMetrics);
    const request = provider.buildRequest('push-token', hint);

    expect(service.providerKind).toBe('apns');
    expect(request.endpoint).toContain('api.sandbox.push.apple.com/3/device/push-token');
    expect(request.headers['apns-topic']).toBe('io.veil.mobile');
    expect(request.body.aps['content-available']).toBe(1);
    expect(request.body.veil).toEqual({ kind: 'wake' });
    const serialized = JSON.stringify(request.body);
    expect(serialized).not.toContain('conversationId');
    expect(serialized).not.toContain('messageId');
    expect(serialized).not.toContain('serverReceivedAt');
    await expect(service.sendMessageHint('push-token', hint)).resolves.toBeUndefined();
  });

  it('builds opaque wake-only FCM requests with no conversation metadata', async () => {
    const provider = new FcmMetadataPushProvider({
      fcmProjectId: 'veil-beta',
      fcmServiceAccountJson: '{"type":"service_account"}',
    } as never);
    const service = new PushService(provider, fakeLogger, fakeMetrics);
    const request = provider.buildRequest('push-token', hint);

    expect(service.providerKind).toBe('fcm');
    expect(request.endpoint).toContain('/projects/veil-beta/messages:send');
    expect(request.body.message.token).toBe('push-token');
    expect(request.body.message.data).toEqual({ kind: 'wake' });
    const serialized = JSON.stringify(request.body);
    expect(serialized).not.toContain('conversationId');
    expect(serialized).not.toContain('messageId');
    expect(serialized).not.toContain('serverReceivedAt');
    await expect(service.sendMessageHint('push-token', hint)).resolves.toBeUndefined();
  });

  it('counts and logs a delivery failure but still resolves (never blocks relay)', async () => {
    const incCalls: Array<Record<string, string>> = [];
    const warnCalls: Array<[string, Record<string, unknown>]> = [];
    const metrics = {
      pushDeliveryTotal: { inc: (l: Record<string, string>) => incCalls.push(l) },
    } as never;
    const logger = {
      info() {},
      error() {},
      warn: (event: string, meta: Record<string, unknown>) => warnCalls.push([event, meta]),
    } as never;
    const provider = {
      kind: 'apns' as const,
      sendMessageHint: async () => {
        throw new Error('410 gone');
      },
    } as never;
    const service = new PushService(provider, logger, metrics);

    await expect(service.sendMessageHint('tok', hint)).resolves.toBeUndefined();
    expect(incCalls).toContainEqual({ provider: 'apns', result: 'failure' });
    expect(warnCalls[0][0]).toBe('push.delivery_failed');
    expect(warnCalls[0][1].error).toEqual({ name: 'Error', code: null });
  });

  it('gives a rejected FCM delivery a code that names only the status', async () => {
    const { privateKey } = generateKeyPairSync('rsa', { modulusLength: 2048 });
    const provider = new FcmMetadataPushProvider({
      fcmProjectId: 'veil-beta',
      fcmServiceAccountJson: JSON.stringify({
        type: 'service_account',
        client_email: 'push@veil-beta.iam.gserviceaccount.com',
        private_key: privateKey.export({ type: 'pkcs8', format: 'pem' }).toString(),
        token_uri: 'https://oauth2.example.test/token',
      }),
      pushDeliveryEnabled: true,
    } as never);
    const fetchMock = jest
      .spyOn(globalThis, 'fetch')
      .mockResolvedValueOnce(
        new Response(JSON.stringify({ access_token: 'at', expires_in: 3600 }), { status: 200 }),
      )
      .mockResolvedValueOnce(
        new Response(
          '{"error":{"status":"NOT_FOUND","message":"Requested entity was not found."}}',
          {
            status: 404,
          },
        ),
      );
    try {
      await expect(provider.sendMessageHint('push-token', hint)).rejects.toMatchObject({
        code: 'fcm_status_404',
      });
    } finally {
      fetchMock.mockRestore();
    }
  });

  it("logs a delivery failure as its class and code, never the provider's response text", async () => {
    const warnCalls: Array<[string, Record<string, unknown>]> = [];
    const metrics = { pushDeliveryTotal: { inc: () => undefined } } as never;
    const logger = {
      info() {},
      error() {},
      warn: (event: string, meta: Record<string, unknown>) => warnCalls.push([event, meta]),
    } as never;
    const body = '{"reason":"BadDeviceToken"}';
    const provider = {
      kind: 'apns' as const,
      sendMessageHint: async () => {
        throw Object.assign(new Error(`APNs delivery failed with status 400: ${body}`), {
          code: 'apns_status_400',
        });
      },
    } as never;
    const service = new PushService(provider, logger, metrics);

    await service.sendMessageHint('device-token', hint);

    expect(warnCalls).toHaveLength(1);
    expect(warnCalls[0][1]).toEqual({
      provider: 'apns',
      pushToken: 'device-token',
      error: { name: 'Error', code: 'apns_status_400' },
    });
    expect(JSON.stringify(warnCalls[0][1])).not.toContain('BadDeviceToken');
  });
});
