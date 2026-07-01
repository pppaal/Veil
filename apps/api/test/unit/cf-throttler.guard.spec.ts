import { CfThrottlerGuard } from '../../src/common/guards/cf-throttler.guard';

// getTracker is protected and stateless (reads only req + process.env), so we
// skip the ThrottlerGuard constructor entirely via Object.create.
function tracker(req: unknown): Promise<string> {
  const guard = Object.create(CfThrottlerGuard.prototype) as {
    getTracker(req: unknown): Promise<string>;
  };
  return guard.getTracker(req);
}

describe('CfThrottlerGuard.getTracker', () => {
  const original = process.env.VEIL_TRUST_PROXY;
  afterEach(() => {
    if (original === undefined) delete process.env.VEIL_TRUST_PROXY;
    else process.env.VEIL_TRUST_PROXY = original;
  });

  it('prefers the authenticated device id (unspoofable, over any header/ip)', async () => {
    process.env.VEIL_TRUST_PROXY = 'true';
    expect(
      await tracker({
        auth: { deviceId: 'd1' },
        headers: { 'cf-connecting-ip': '1.2.3.4' },
        ip: '9.9.9.9',
      }),
    ).toBe('dev:d1');
  });

  it('IGNORES cf-connecting-ip when VEIL_TRUST_PROXY is unset (anti-spoof)', async () => {
    delete process.env.VEIL_TRUST_PROXY;
    expect(await tracker({ headers: { 'cf-connecting-ip': '1.2.3.4' }, ip: '9.9.9.9' })).toBe(
      'ip:9.9.9.9',
    );
  });

  it('uses cf-connecting-ip only when VEIL_TRUST_PROXY==="true"', async () => {
    process.env.VEIL_TRUST_PROXY = 'true';
    expect(await tracker({ headers: { 'cf-connecting-ip': ' 1.2.3.4 ' }, ip: '9.9.9.9' })).toBe(
      'cf:1.2.3.4',
    );
  });

  it('takes the first entry when cf-connecting-ip is an array', async () => {
    process.env.VEIL_TRUST_PROXY = 'true';
    expect(
      await tracker({ headers: { 'cf-connecting-ip': ['1.2.3.4', '5.6.7.8'] }, ip: '9.9.9.9' }),
    ).toBe('cf:1.2.3.4');
  });

  it('falls back to req.ip when trusted but the cf header is absent', async () => {
    process.env.VEIL_TRUST_PROXY = 'true';
    expect(await tracker({ headers: {}, ip: '9.9.9.9' })).toBe('ip:9.9.9.9');
  });

  it('falls back to ip:unknown when no ip is present', async () => {
    delete process.env.VEIL_TRUST_PROXY;
    expect(await tracker({ headers: {} })).toBe('ip:unknown');
  });
});
