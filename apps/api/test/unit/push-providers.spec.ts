import { generateKeyPairSync } from 'node:crypto';
import * as http2 from 'node:http2';
import type { AddressInfo } from 'node:net';

import { ApnsMetadataPushProvider } from '../../src/modules/push/apns-push.provider';
import { FcmMetadataPushProvider } from '../../src/modules/push/fcm-push.provider';

// Wakes run after the message is relayed, but a provider that never settles
// would still pile up open sessions and pending promises, so each provider
// gives up on its own.

jest.mock('node:http2', () => {
  const actual = jest.requireActual('node:http2');
  return { ...actual, connect: jest.fn(actual.connect) };
});

const realHttp2 = jest.requireActual<typeof http2>('node:http2');

describe('ApnsMetadataPushProvider', () => {
  let server: http2.Http2Server;
  let port: number;
  const openStreams: http2.ServerHttp2Stream[] = [];
  const closedStreams: number[] = [];

  beforeAll(async () => {
    // Accepts every stream and never answers, like an APNs peer that stalls.
    server = realHttp2.createServer();
    server.on('stream', (stream) => {
      openStreams.push(stream);
      stream.on('close', () => closedStreams.push(stream.id ?? 0));
      stream.resume();
    });
    await new Promise<void>((resolve) => server.listen(0, '127.0.0.1', resolve));
    port = (server.address() as AddressInfo).port;
  });

  afterAll(async () => {
    for (const stream of openStreams) stream.destroy();
    await new Promise<void>((resolve) => server.close(() => resolve()));
  });

  it('rejects with apns_timeout and closes the session when the peer stalls', async () => {
    (http2.connect as jest.Mock).mockImplementation(() =>
      realHttp2.connect(`http://127.0.0.1:${port}`),
    );
    const { privateKey } = generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
    const provider = new ApnsMetadataPushProvider(
      {
        apnsBundleId: 'org.veil.test',
        apnsTeamId: 'TEAM123456',
        apnsKeyId: 'KEY1234567',
        apnsPrivateKeyPem: privateKey.export({ type: 'pkcs8', format: 'pem' }).toString(),
        apnsUseSandbox: true,
        pushDeliveryEnabled: true,
      } as never,
      200,
    );

    const startedAt = Date.now();
    await expect(provider.sendMessageHint('a'.repeat(64), { kind: 'wake' })).rejects.toMatchObject({
      code: 'apns_timeout',
    });
    expect(Date.now() - startedAt).toBeLessThan(5_000);
    expect(openStreams).toHaveLength(1);

    // The client destroyed its session, so the server sees the stream close.
    const deadline = Date.now() + 5_000;
    while (closedStreams.length === 0 && Date.now() < deadline) {
      await new Promise((resolve) => setTimeout(resolve, 20));
    }
    expect(closedStreams).toHaveLength(1);
  });
});

describe('FcmMetadataPushProvider', () => {
  const originalFetch = global.fetch;

  afterEach(() => {
    global.fetch = originalFetch;
  });

  it('bounds both the token request and the send with an abort signal', async () => {
    const { privateKey } = generateKeyPairSync('rsa', { modulusLength: 2048 });
    const provider = new FcmMetadataPushProvider({
      fcmProjectId: 'veil-test',
      fcmServiceAccountJson: JSON.stringify({
        client_email: 'push@veil-test.iam.gserviceaccount.com',
        private_key: privateKey.export({ type: 'pkcs8', format: 'pem' }).toString(),
      }),
      pushDeliveryEnabled: true,
    } as never);
    const requests: Array<{ url: string; signal: unknown }> = [];
    global.fetch = jest.fn(async (url: string | URL | Request, init?: RequestInit) => {
      requests.push({ url: String(url), signal: init?.signal });
      return String(url).includes('oauth2')
        ? new Response(JSON.stringify({ access_token: 'token', expires_in: 3600 }))
        : new Response('{}');
    }) as typeof fetch;

    await provider.sendMessageHint('device-token', { kind: 'wake' });

    expect(requests.map((request) => new URL(request.url).host)).toEqual([
      'oauth2.googleapis.com',
      'fcm.googleapis.com',
    ]);
    for (const request of requests) {
      expect(request.signal).toBeInstanceOf(AbortSignal);
    }
  });
});
