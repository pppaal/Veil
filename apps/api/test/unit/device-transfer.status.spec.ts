import { createHash } from 'node:crypto';

import { DeviceTransferService } from '../../src/modules/device-transfer/device-transfer.service';

// Complements device-transfer.service.spec.ts (happy path / expiry / TOCTOU /
// replay). This file covers getSessionStatus's state machine and the granular
// approve/claim/complete rejection codes, all via lightweight mocks.

const hashToken = (t: string) => createHash('sha256').update(t).digest('hex');
const AUTH = { userId: 'u1', deviceId: 'd1' };

function make(
  opts: {
    session?: Record<string, unknown> | null;
    pendingClaim?: unknown;
    proofValid?: boolean;
    oldDevice?: { isActive: boolean; revokedAt: Date | null };
  } = {},
) {
  const oldDevice = opts.oldDevice ?? { isActive: true, revokedAt: null };
  const prisma = {
    deviceTransferSession: {
      findUnique: async () =>
        opts.session
          ? { oldDevice, user: { handle: 'a', displayName: null }, ...opts.session }
          : null,
      update: async () => ({}),
    },
    device: { findUnique: async () => oldDevice },
  };
  const ephemeralStore = {
    getJson: async () => opts.pendingClaim ?? null,
    setJson: async () => undefined,
    delete: async () => undefined,
  };
  const config = { transferTokenTtlSeconds: 300 };
  const verifier = { verifyChallengeResponse: async () => opts.proofValid ?? true };
  const realtime = { disconnectDevice: () => undefined };
  return new DeviceTransferService(
    prisma as never,
    ephemeralStore as never,
    config as never,
    verifier as never,
    realtime as never,
  );
}

const activeSession = (over: Record<string, unknown> = {}) => ({
  id: 's1',
  userId: 'u1',
  oldDeviceId: 'd1',
  tokenHash: hashToken('good-token'),
  completedAt: null,
  expiresAt: new Date(Date.now() + 60_000),
  ...over,
});

const claim = (over: Record<string, unknown> = {}) => ({
  claimId: 'claim-1',
  claimantFingerprint: 'ab...cd',
  newDeviceName: 'New Phone',
  platform: 'ios',
  authPublicKey: 'pub',
  publicIdentityKey: 'id',
  signedPrekeyBundle: 'spk',
  ...over,
});

describe('DeviceTransferService.getSessionStatus (state machine)', () => {
  const status = (session: Record<string, unknown> | null, pendingClaim?: unknown) =>
    make({ session, pendingClaim }).getSessionStatus({ sessionId: 's1', auth: AUTH });

  it('404s an unknown session', async () => {
    await expect(status(null)).rejects.toMatchObject({
      response: { code: 'transfer_session_not_found' },
    });
  });

  it('404s a session owned by a different user (no existence leak)', async () => {
    await expect(status(activeSession({ userId: 'someone-else' }))).rejects.toMatchObject({
      response: { code: 'transfer_session_not_found' },
    });
  });

  it('reports completed / expired / approved / claimed / pending', async () => {
    expect((await status(activeSession({ completedAt: new Date() }))).status).toBe('completed');
    expect((await status(activeSession({ expiresAt: new Date(Date.now() - 1000) }))).status).toBe(
      'expired',
    );
    expect(
      (await status(activeSession(), claim({ approvedAt: new Date().toISOString() }))).status,
    ).toBe('approved');
    expect((await status(activeSession(), claim())).status).toBe('claimed');
    expect((await status(activeSession(), null)).status).toBe('pending');
  });
});

describe('DeviceTransferService.approve', () => {
  const approve = (svc: DeviceTransferService, claimId = 'claim-1') =>
    svc.approve(AUTH, { sessionId: 's1', claimId } as never);

  it('404s an unknown session', async () => {
    await expect(approve(make({ session: null }))).rejects.toMatchObject({
      response: { code: 'transfer_session_not_found' },
    });
  });

  it('requires a matching pending claim', async () => {
    await expect(
      approve(make({ session: activeSession(), pendingClaim: null })),
    ).rejects.toMatchObject({ response: { code: 'transfer_claim_required' } });
    await expect(
      approve(make({ session: activeSession(), pendingClaim: claim({ claimId: 'other' }) })),
    ).rejects.toMatchObject({ response: { code: 'transfer_claim_required' } });
  });

  it('approves when a matching claim exists', async () => {
    const res = await approve(make({ session: activeSession(), pendingClaim: claim() }));
    expect(res).toEqual({ sessionId: 's1', claimId: 'claim-1', approved: true });
  });
});

describe('DeviceTransferService.claim rejections', () => {
  const dto = (over: Record<string, unknown> = {}) =>
    ({
      sessionId: 's1',
      transferToken: 'good-token',
      newDeviceName: 'New Phone',
      platform: 'ios',
      publicIdentityKey: 'id',
      signedPrekeyBundle: 'spk',
      authPublicKey: 'pub',
      authProof: 'proof',
      ...over,
    }) as never;

  it('rejects an invalid transfer token', async () => {
    await expect(
      make({ session: activeSession() }).claim(dto({ transferToken: 'wrong' })),
    ).rejects.toMatchObject({ response: { code: 'transfer_token_invalid' } });
  });

  it('rejects an invalid new-device proof', async () => {
    await expect(
      make({ session: activeSession(), proofValid: false }).claim(dto()),
    ).rejects.toMatchObject({ response: { code: 'transfer_claim_invalid' } });
  });
});

describe('DeviceTransferService.complete rejections', () => {
  const dto = (over: Record<string, unknown> = {}) =>
    ({
      sessionId: 's1',
      claimId: 'claim-1',
      transferToken: 'good-token',
      authProof: 'proof',
      ...over,
    }) as never;

  it('requires a matching claim', async () => {
    await expect(
      make({ session: activeSession(), pendingClaim: null }).complete(dto()),
    ).rejects.toMatchObject({ response: { code: 'transfer_claim_required' } });
  });

  it('requires old-device approval before completion', async () => {
    // pendingClaim present + matching id, but not yet approved.
    await expect(
      make({ session: activeSession(), pendingClaim: claim() }).complete(dto()),
    ).rejects.toMatchObject({ response: { code: 'transfer_approval_required' } });
  });

  it('rejects an invalid completion proof', async () => {
    await expect(
      make({
        session: activeSession(),
        pendingClaim: claim({ approvedAt: new Date().toISOString() }),
        proofValid: false,
      }).complete(dto()),
    ).rejects.toMatchObject({ response: { code: 'transfer_completion_invalid' } });
  });
});
