import {
  UnifiedPushProvider,
  isPrivateHost,
} from '../../src/modules/push/unifiedpush-push.provider';

const hint = { kind: 'wake' as const };

const configWith = (
  overrides: Partial<{
    pushDeliveryEnabled: boolean;
    unifiedPushAllowedHosts: string[];
  }> = {},
) =>
  ({
    pushDeliveryEnabled: overrides.pushDeliveryEnabled ?? false,
    unifiedPushAllowedHosts: overrides.unifiedPushAllowedHosts ?? [],
  }) as never;

describe('UnifiedPushProvider', () => {
  it('reports the unifiedpush kind', () => {
    const provider = new UnifiedPushProvider(configWith());
    expect(provider.kind).toBe('unifiedpush');
  });

  it('builds an opaque, wake-only request to the device endpoint', () => {
    const provider = new UnifiedPushProvider(configWith());
    const request = provider.buildRequest('https://ntfy.sh/up?id=abc123', hint);

    expect(request.endpoint).toBe('https://ntfy.sh/up?id=abc123');
    expect(request.headers['Content-Type']).toBe('application/json');
    expect(request.headers.TTL).toBe('86400');

    const serialized = request.body;
    expect(JSON.parse(serialized)).toEqual({ kind: 'wake' });
    // The wake carries no conversation metadata, matching APNs/FCM.
    expect(serialized).not.toContain('conversationId');
    expect(serialized).not.toContain('messageId');
    expect(serialized).not.toContain('serverReceivedAt');
  });

  it('rejects non-https endpoints', () => {
    const provider = new UnifiedPushProvider(configWith());
    expect(() => provider.buildRequest('http://ntfy.sh/up?id=abc', hint)).toThrow(/https/);
  });

  it('rejects malformed endpoint URLs', () => {
    const provider = new UnifiedPushProvider(configWith());
    expect(() => provider.buildRequest('not a url', hint)).toThrow(/valid URL/);
  });

  it('rejects private/loopback/metadata addresses (SSRF guard) when no allowlist is set', () => {
    const provider = new UnifiedPushProvider(configWith());
    for (const evil of [
      'https://127.0.0.1/up',
      'https://localhost/up',
      'https://169.254.169.254/latest/meta-data',
      'https://10.0.0.5/up',
      'https://192.168.1.20/up',
      'https://[::1]/up',
    ]) {
      expect(() => provider.buildRequest(evil, hint)).toThrow(/private address/);
    }
  });

  it('enforces the host allowlist when configured, overriding the IP screen', () => {
    const provider = new UnifiedPushProvider(configWith({ unifiedPushAllowedHosts: ['ntfy.sh'] }));
    // Allowlisted host passes.
    expect(() => provider.buildRequest('https://ntfy.sh/up?id=ok', hint)).not.toThrow();
    // A public but non-allowlisted host is refused.
    expect(() => provider.buildRequest('https://evil.example/up', hint)).toThrow(/allowlisted/);
  });

  it('does not call out when delivery is disabled', async () => {
    const fetchSpy = jest.spyOn(globalThis, 'fetch');
    const provider = new UnifiedPushProvider(configWith({ pushDeliveryEnabled: false }));

    await expect(
      provider.sendMessageHint('https://ntfy.sh/up?id=abc', hint),
    ).resolves.toBeUndefined();
    expect(fetchSpy).not.toHaveBeenCalled();
    fetchSpy.mockRestore();
  });

  it('POSTs the wake and surfaces a non-2xx as a throw when delivery is enabled', async () => {
    const calls: Array<{ url: string; init: RequestInit }> = [];
    const fetchSpy = jest
      .spyOn(globalThis, 'fetch')
      .mockImplementation((url: string | URL | Request, init?: RequestInit) => {
        calls.push({ url: String(url), init: init ?? {} });
        return Promise.resolve({ ok: true, status: 200 } as Response);
      });
    const provider = new UnifiedPushProvider(configWith({ pushDeliveryEnabled: true }));

    await provider.sendMessageHint('https://ntfy.sh/up?id=abc', hint);
    expect(calls).toHaveLength(1);
    expect(calls[0].url).toBe('https://ntfy.sh/up?id=abc');
    expect(calls[0].init.method).toBe('POST');

    fetchSpy.mockImplementation(() => Promise.resolve({ ok: false, status: 502 } as Response));
    await expect(provider.sendMessageHint('https://ntfy.sh/up?id=abc', hint)).rejects.toThrow(
      /502/,
    );

    fetchSpy.mockRestore();
  });
});

describe('isPrivateHost', () => {
  it.each([
    'localhost',
    'foo.localhost',
    '127.0.0.1',
    '10.1.2.3',
    '172.16.0.1',
    '172.31.255.255',
    '192.168.0.1',
    '169.254.169.254',
    '100.64.0.1',
    '0.0.0.0',
    '::1',
    'fe80::1',
    'fc00::1',
    'fd12:3456::1',
    '::ffff:127.0.0.1',
  ])('flags %s as private', (host) => {
    expect(isPrivateHost(host)).toBe(true);
  });

  it.each(['ntfy.sh', 'push.example.org', '8.8.8.8', '172.32.0.1', '100.128.0.1'])(
    'allows public host %s',
    (host) => {
      expect(isPrivateHost(host)).toBe(false);
    },
  );
});
