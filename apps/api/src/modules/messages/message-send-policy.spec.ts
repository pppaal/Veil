import { assertEnvelopeAccepted, resolveExpiresAt } from './message-send-policy';

const now = new Date('2026-06-01T12:00:00.000Z');
const at = (offsetMs: number) => new Date(now.getTime() + offsetMs).toISOString();

describe('resolveExpiresAt', () => {
  it('leaves expiry off without a timer or a client value', () => {
    expect(resolveExpiresAt(undefined, null, now)).toBeNull();
  });

  it('tolerates a minute of clock skew in the past', () => {
    expect(resolveExpiresAt(at(-59_000), null, now)?.toISOString()).toBe(at(-59_000));
    expect(() => resolveExpiresAt(at(-61_000), null, now)).toThrow('expiresAt is in the past');
  });

  it('caps client values at 30 days', () => {
    const thirtyDays = 30 * 24 * 3600_000;
    expect(resolveExpiresAt(at(thirtyDays), null, now)?.toISOString()).toBe(at(thirtyDays));
    expect(() => resolveExpiresAt(at(thirtyDays + 1), null, now)).toThrow('30 days');
  });

  it('keeps values within five minutes past the timer and clamps beyond', () => {
    expect(resolveExpiresAt(at(3600_000 + 300_000), 3600, now)?.toISOString()).toBe(
      at(3600_000 + 300_000),
    );
    expect(resolveExpiresAt(at(3600_000 + 300_001), 3600, now)?.toISOString()).toBe(at(3600_000));
  });

  it('rejects an unparseable timestamp', () => {
    expect(() => resolveExpiresAt('tomorrow', null, now)).toThrow('ISO-8601');
  });
});

describe('assertEnvelopeAccepted', () => {
  const direct = { type: 'direct' as const, groupUseSenderKeys: false };
  const senderKeysGroup = { type: 'group' as const, groupUseSenderKeys: true };
  const channel = { type: 'channel' as const, groupUseSenderKeys: false };

  it.each(['veil-envelope-v1', 'veil-envelope-v1-dev', 'veil-envelope-v2', 'libsignal-v1'])(
    'accepts pairwise %s in direct chats and channels',
    (version) => {
      expect(() => assertEnvelopeAccepted(direct, { version }, false)).not.toThrow();
      expect(() => assertEnvelopeAccepted(channel, { version }, false)).not.toThrow();
      expect(() => assertEnvelopeAccepted(senderKeysGroup, { version }, false)).toThrow();
    },
  );

  it('accepts only veil-group-v1 in a Sender Keys group', () => {
    expect(() =>
      assertEnvelopeAccepted(senderKeysGroup, { version: 'veil-group-v1' }, false),
    ).not.toThrow();
    expect(() => assertEnvelopeAccepted(direct, { version: 'veil-group-v1' }, false)).toThrow();
  });

  it('rejects unknown versions everywhere', () => {
    expect(() => assertEnvelopeAccepted(direct, { version: 'veil.v1' }, false)).toThrow();
  });

  it('refuses development markers only in production', () => {
    const devWrap = {
      version: 'veil-envelope-v1',
      attachment: { encryption: { algorithmHint: 'dev-wrap' } },
    };
    expect(() => assertEnvelopeAccepted(direct, devWrap, false)).not.toThrow();
    expect(() => assertEnvelopeAccepted(direct, devWrap, true)).toThrow(
      'Development envelope formats',
    );
    expect(() => assertEnvelopeAccepted(direct, { version: 'veil-envelope-v1-dev' }, true)).toThrow(
      'Development envelope formats',
    );
  });
});
