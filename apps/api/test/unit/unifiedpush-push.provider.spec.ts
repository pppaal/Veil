import { createServer, type Server } from 'node:http';
import type { AddressInfo } from 'node:net';

import {
  guardedLookup,
  isForbiddenAddress,
  validatePushEndpointUrl,
  type AddressResolver,
} from '../../src/modules/push/push-endpoint.validator';
import { NoopPushProvider, PushService } from '../../src/modules/push/push.service';
import {
  UnifiedPushProvider,
  type PushHttpTransport,
} from '../../src/modules/push/unifiedpush-push.provider';

const hint = { kind: 'wake' as const };

const configWith = (
  overrides: Partial<{
    pushDeliveryEnabled: boolean;
    unifiedPushAllowedHosts: string[];
    isProduction: boolean;
  }> = {},
) =>
  ({
    pushDeliveryEnabled: overrides.pushDeliveryEnabled ?? false,
    unifiedPushAllowedHosts: overrides.unifiedPushAllowedHosts ?? [],
    isProduction: overrides.isProduction ?? true,
  }) as never;

const resolvingTo =
  (...addresses: string[]): AddressResolver =>
  async () =>
    addresses.map((address) => ({ address, family: address.includes(':') ? 6 : 4 }));

const recordingMetrics = () => {
  const results: Array<Record<string, string>> = [];
  return {
    results,
    metrics: {
      pushDeliveryTotal: { inc: (labels: Record<string, string>) => results.push(labels) },
    },
  };
};

const silentLogger = { info() {}, warn() {}, error() {} } as never;

describe('UnifiedPushProvider', () => {
  it('builds an opaque, wake-only request to the device endpoint', () => {
    const provider = new UnifiedPushProvider(configWith());
    const request = provider.buildRequest('https://ntfy.sh/up?id=abc123', hint);

    expect(provider.kind).toBe('unifiedpush');
    expect(request.endpoint).toBe('https://ntfy.sh/up?id=abc123');
    expect(request.headers['Content-Type']).toBe('application/json');
    expect(request.headers.TTL).toBe('86400');
    expect(JSON.parse(request.body)).toEqual({ kind: 'wake' });
    expect(request.body).not.toContain('conversationId');
    expect(request.body).not.toContain('messageId');
  });

  it('does not call out when delivery is disabled', async () => {
    const transport = jest.fn<ReturnType<PushHttpTransport>, Parameters<PushHttpTransport>>();
    const provider = new UnifiedPushProvider(configWith(), transport);

    await expect(
      provider.sendMessageHint('https://ntfy.sh/up?id=abc', hint),
    ).resolves.toBeUndefined();
    expect(transport).not.toHaveBeenCalled();
  });

  it('POSTs the wake through the guarded lookup and reports only the status class', async () => {
    const transport = jest
      .fn<ReturnType<PushHttpTransport>, Parameters<PushHttpTransport>>()
      .mockResolvedValueOnce(201)
      .mockResolvedValueOnce(502);
    const lookup = guardedLookup(resolvingTo('93.184.216.34'));
    const provider = new UnifiedPushProvider(
      configWith({ pushDeliveryEnabled: true }),
      transport,
      lookup,
    );

    await provider.sendMessageHint('https://ntfy.sh/up?id=abc', hint);
    const [url, request] = transport.mock.calls[0]!;
    expect(url.toString()).toBe('https://ntfy.sh/up?id=abc');
    expect(request.lookup).toBe(lookup);
    expect(request.timeoutMs).toBe(10_000);

    const failure = provider.sendMessageHint('https://ntfy.sh/up?id=abc', hint);
    await expect(failure).rejects.toThrow('UnifiedPush delivery failed with status class 5xx');
    await expect(failure).rejects.not.toThrow(/ntfy|abc/);
  });

  describe('against a real HTTP server', () => {
    let server: Server;
    let hits: string[];
    let port: number;

    beforeEach(async () => {
      hits = [];
      server = createServer((req, res) => {
        hits.push(req.url ?? '');
        if (req.url?.startsWith('/redirect')) {
          res.writeHead(307, { Location: `http://localhost:${port}/internal` });
        } else {
          res.writeHead(200);
        }
        res.end();
      });
      await new Promise<void>((resolve) => server.listen(0, '127.0.0.1', resolve));
      port = (server.address() as AddressInfo).port;
    });

    afterEach(async () => {
      await new Promise<void>((resolve) => server.close(() => resolve()));
    });

    it('307 not followed and counts as failure', async () => {
      const provider = new UnifiedPushProvider(
        configWith({ pushDeliveryEnabled: true, isProduction: false }),
      );
      const { metrics, results } = recordingMetrics();
      const service = new PushService(provider, silentLogger, metrics as never);

      await expect(
        provider.sendMessageHint(`http://localhost:${port}/redirect`, hint),
      ).rejects.toThrow('status class 3xx');
      await service.sendMessageHint(`http://localhost:${port}/redirect`, hint);

      expect(hits).toEqual(['/redirect', '/redirect']);
      expect(results).toEqual([{ provider: 'unifiedpush', result: 'failure' }]);
    });

    it('delivers to a development localhost distributor', async () => {
      const provider = new UnifiedPushProvider(
        configWith({ pushDeliveryEnabled: true, isProduction: false }),
      );

      await provider.sendMessageHint(`http://localhost:${port}/up`, hint);
      expect(hits).toEqual(['/up']);
    });
  });

  it('host resolving to 10.0.0.5 rejected', async () => {
    const resolver = jest.fn(resolvingTo('10.0.0.5'));
    const provider = new UnifiedPushProvider(
      configWith({ pushDeliveryEnabled: true, unifiedPushAllowedHosts: ['push.example.org'] }),
      undefined,
      guardedLookup(resolver),
    );

    await expect(provider.sendMessageHint('https://push.example.org/up', hint)).rejects.toThrow(
      'UnifiedPush delivery failed: EPUSHPRIVATE',
    );
    expect(resolver).toHaveBeenCalledWith('push.example.org');
  });

  it('::ffff:127.0.0.1 rejected', () => {
    const provider = new UnifiedPushProvider(configWith());
    expect(() => provider.buildRequest('https://[::ffff:127.0.0.1]/up', hint)).toThrow(
      /private address/,
    );
  });

  it('is a drop-in PushService provider like the noop one', async () => {
    const { metrics, results } = recordingMetrics();
    await new PushService(new NoopPushProvider(), silentLogger, metrics as never).sendMessageHint(
      'token',
      hint,
    );
    expect(results).toEqual([{ provider: 'none', result: 'success' }]);
  });
});

describe('guardedLookup', () => {
  const lookupOnce = (resolver: AddressResolver, all: boolean) =>
    new Promise<{ error: NodeJS.ErrnoException | null; address: unknown; family?: number }>(
      (resolve) =>
        guardedLookup(resolver)('push.example.org', { all }, (error, address, family) =>
          resolve({ error, address, family }),
        ),
    );

  it('refuses the whole answer when ANY resolved address is private', async () => {
    const { error } = await lookupOnce(resolvingTo('93.184.216.34', '192.168.1.10'), true);
    expect(error?.code).toBe('EPUSHPRIVATE');
  });

  it('returns vetted public addresses in both lookup shapes', async () => {
    const resolver = resolvingTo('93.184.216.34', '2606:2800:220:1::248');
    await expect(lookupOnce(resolver, true)).resolves.toMatchObject({
      error: null,
      address: [
        { address: '93.184.216.34', family: 4 },
        { address: '2606:2800:220:1::248', family: 6 },
      ],
    });
    await expect(lookupOnce(resolver, false)).resolves.toMatchObject({
      error: null,
      address: '93.184.216.34',
      family: 4,
    });
  });
});

describe('validatePushEndpointUrl', () => {
  const production = { allowedHosts: [], production: true };

  it.each([
    ['http://ntfy.sh/up', /https/],
    ['not a url', /valid URL/],
    ['https://user:pw@ntfy.sh/up', /credentials/],
    ['https://localhost/up', /localhost/],
    ['https://127.0.0.1/up', /private address/],
    ['https://0x7f.1/up', /private address/],
    ['https://10.1.2.3/up', /private address/],
    ['https://172.16.0.1/up', /private address/],
    ['https://192.168.0.1/up', /private address/],
    ['https://169.254.169.254/latest/meta-data', /private address/],
    ['https://100.64.0.1/up', /private address/],
    ['https://0.0.0.0/up', /private address/],
    ['https://224.0.0.1/up', /private address/],
    ['https://[::1]/up', /private address/],
    ['https://[::]/up', /private address/],
    ['https://[fe80::1]/up', /private address/],
    ['https://[fd12:3456::1]/up', /private address/],
    ['https://[ff02::1]/up', /private address/],
    ['https://[::ffff:10.0.0.5]/up', /private address/],
  ])('rejects %s in production', (endpoint, reason) => {
    expect(() => validatePushEndpointUrl(endpoint, production)).toThrow(reason);
  });

  it('allows plain http only for localhost outside production', () => {
    const development = { allowedHosts: [], production: false };
    expect(validatePushEndpointUrl('http://localhost:8080/up', development).port).toBe('8080');
    expect(() => validatePushEndpointUrl('http://ntfy.sh/up', development)).toThrow(/https/);
    expect(() => validatePushEndpointUrl('http://127.0.0.1/up', development)).toThrow(
      /https|private/,
    );
  });

  it('enforces a non-empty allowlist by exact host or subdomain', () => {
    const policy = { allowedHosts: ['ntfy.sh'], production: true };
    expect(validatePushEndpointUrl('https://ntfy.sh/up', policy).hostname).toBe('ntfy.sh');
    expect(validatePushEndpointUrl('https://eu.ntfy.sh/up', policy).hostname).toBe('eu.ntfy.sh');
    expect(() => validatePushEndpointUrl('https://evilntfy.sh/up', policy)).toThrow(/allowlisted/);
    expect(() => validatePushEndpointUrl('https://ntfy.sh.evil.example/up', policy)).toThrow(
      /allowlisted/,
    );
  });

  it.each(['ntfy.sh', '8.8.8.8', '172.32.0.1', '100.128.0.1', '2606:4700::1111'])(
    'treats %s as reachable',
    (host) => {
      expect(isForbiddenAddress(host)).toBe(false);
    },
  );
});
