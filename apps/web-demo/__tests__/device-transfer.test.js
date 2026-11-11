import { describe, expect, it, vi } from 'vitest';
import { webcrypto } from 'node:crypto';

import { generateIdentity } from '../src/crypto/identity.js';
import { watchOldDeviceTransfer } from '../src/features/device-transfer.js';
import { createApiClient } from '../src/platform/api-client.js';
import { createSessionStore } from '../src/platform/session-store.js';

const { subtle } = webcrypto;
const SESSION_ID = '3b9f6c1e-2a4d-4e8f-9b0a-1c2d3e4f5a6b';
const CLAIM = { claimId: 'claim-1', claimantFingerprint: 'ab12 cd34', newDeviceName: 'web', platform: 'android' };

// The API as the old device sees it. complete() is the new device's
// /device-transfer/complete: like DeviceTransferService.complete it marks
// the session completed and revokes the old device in one step, after which
// the JWT guard, /auth/refresh and /auth/challenge all refuse the old device.
function fakeTransferApi() {
  const server = {
    deviceActive: true,
    completedAt: null,
    expired: false,
    claimed: false,
    approvedClaimId: null,
    // Runs before each status read is answered; lets a test move the server
    // along at a precise point in the poll.
    beforeStatusRead: null,
    calls: [],
    complete() {
      server.completedAt = '2026-11-11T10:00:00.000Z';
      server.deviceActive = false;
    },
  };
  const refused = [401, { code: 'device_not_active', message: 'Device is not active' }];
  const guarded = (handler) => (request) => (server.deviceActive ? handler(request) : refused);
  const status = () => {
    if (server.completedAt) return 'completed';
    if (server.expired) return 'expired';
    if (server.approvedClaimId) return 'approved';
    return server.claimed ? 'claimed' : 'pending';
  };
  const routes = {
    '/auth/refresh': guarded(() => [200, { accessToken: 'access-2', refreshToken: 'refresh-2' }]),
    '/auth/challenge': guarded(() => [200, { challengeId: 'ch-1', challenge: 'sign-me' }]),
    '/auth/verify': guarded(() => [200, { accessToken: 'access-3', refreshToken: 'refresh-3', userId: 'user-1' }]),
    [`/device-transfer/sessions/${SESSION_ID}`]: (request) => {
      server.beforeStatusRead?.();
      return guarded(() => [200, {
        sessionId: SESSION_ID,
        status: status(),
        completedAt: server.completedAt,
        pendingClaim: server.claimed ? { ...CLAIM, approvedAt: server.approvedClaimId ? '2026-11-11T09:59:00.000Z' : null } : null,
      }])(request);
    },
    '/device-transfer/approve': guarded(({ body }) => {
      expect(body).toEqual({ sessionId: SESSION_ID, claimId: CLAIM.claimId });
      server.approvedClaimId = body.claimId;
      return [200, { sessionId: SESSION_ID, claimId: body.claimId, approvedAt: '2026-11-11T09:59:00.000Z' }];
    }),
  };
  const fetchImpl = vi.fn(async (url, init) => {
    const path = url.replace('/v1', '');
    const body = init.body ? JSON.parse(init.body) : undefined;
    server.calls.push(path);
    const route = routes[path];
    const [code, payload] = route ? route({ body }) : [404, { message: 'no route' }];
    return { ok: code >= 200 && code < 300, status: code, text: async () => JSON.stringify(payload) };
  });
  return { server, fetchImpl };
}

// The old device: a signed-in session store and an API client whose
// onSessionRejected asks the transfer first, the way app.js wires it.
async function oldDevice() {
  const api = fakeTransferApi();
  let value = {
    handle: 'alice',
    userId: 'user-1',
    deviceId: 'device-old',
    ...(await generateIdentity(subtle)),
    accessToken: 'access-1',
    refreshToken: 'refresh-1',
  };
  const store = createSessionStore({ repo: { get: async () => value, put: async (next) => { value = next; } }, subtle });
  await store.load();
  const rejections = [];
  let transfer = null;
  const client = createApiClient({
    fetchImpl: api.fetchImpl,
    baseUrl: '/v1',
    tokenStore: store,
    onSessionRejected: () => { rejections.push(transfer.sessionEnded()); },
  });
  const watch = (options = {}) => {
    transfer = watchOldDeviceTransfer({
      sessionId: SESSION_ID,
      authedApi: client.authedApi,
      sleep: () => new Promise((resolve) => setTimeout(resolve, 0)),
      ...options,
    });
    return transfer;
  };
  return { ...api, store, rejections, watch, stored: () => value };
}

describe('watchOldDeviceTransfer', () => {
  it('a completion that revokes this device settles as completed', async () => {
    const device = await oldDevice();
    const transfer = device.watch({
      onClaim: (claim) => {
        expect(claim.claimantFingerprint).toBe(CLAIM.claimantFingerprint);
        transfer.approve().then(() => device.server.complete());
      },
    });
    device.server.claimed = true;

    await expect(transfer.outcome).resolves.toBe('completed');
    // The status endpoint never answered 'completed': the device was revoked
    // first, recovery was refused and the session was rejected.
    expect(device.server.calls).toContain('/auth/refresh');
    expect(device.server.calls).toContain('/auth/challenge');
    expect(await Promise.all(device.rejections)).toEqual(['completed']);
    expect(device.store.getAccessToken()).toBeNull();
  });

  it('a rejected session without an approval keeps the identity', async () => {
    const device = await oldDevice();
    const onClaim = vi.fn();
    const transfer = device.watch({ onClaim });
    device.server.claimed = true;
    device.server.beforeStatusRead = () => {
      if (onClaim.mock.calls.length > 0) device.server.deviceActive = false;
    };

    await expect(transfer.outcome).resolves.toBe('session-ended');
    expect(await Promise.all(device.rejections)).toEqual(['session-ended']);
    expect(device.stored().edPrivKey).toBeDefined();
    expect(device.stored().xPrivKey).toBeDefined();
  });

  it('an approval still in flight when the session is rejected counts', async () => {
    const device = await oldDevice();
    let releaseApprove;
    const approveGate = new Promise((resolve) => { releaseApprove = resolve; });
    const realFetch = device.fetchImpl.getMockImplementation();
    device.fetchImpl.mockImplementation(async (url, init) => {
      const response = await realFetch(url, init);
      // The server applied the approval and the new device completed at
      // once; the approve response is still on its way back.
      if (url.endsWith('/device-transfer/approve')) {
        device.server.complete();
        await approveGate;
      }
      return response;
    });
    let approving = null;
    const transfer = device.watch({ onClaim: () => { approving = transfer.approve(); } });
    device.server.claimed = true;

    await vi.waitFor(() => expect(device.rejections).toHaveLength(1));
    releaseApprove();
    await expect(transfer.outcome).resolves.toBe('completed');
    await expect(approving).resolves.toBe(true);
  });

  it('a closed session read with a working session is not a completion', async () => {
    const device = await oldDevice();
    const transfer = device.watch({ onClaim: () => transfer.approve() });
    device.server.claimed = true;
    device.server.beforeStatusRead = () => {
      // A newer transfer replaced this one: closed, and this device untouched.
      if (device.server.approvedClaimId) device.server.completedAt = '2026-11-11T10:00:00.000Z';
    };

    await expect(transfer.outcome).resolves.toBe('closed');
    expect(device.rejections).toEqual([]);
    expect(device.store.getAccessToken()).toBe('access-1');
  });

  it('a completion that lands between the auth check and the read is confirmed by the next poll', async () => {
    const device = await oldDevice();
    const transfer = device.watch({ onClaim: () => transfer.approve() });
    device.server.claimed = true;
    let racedOnce = false;
    device.server.beforeStatusRead = () => {
      if (!device.server.approvedClaimId || racedOnce) return;
      racedOnce = true;
      // This read passed the guard; the transaction commits before it answers.
      device.server.completedAt = '2026-11-11T10:00:00.000Z';
      setTimeout(() => { device.server.deviceActive = false; }, 0);
    };

    await expect(transfer.outcome).resolves.toBe('completed');
  });

  it('without an approval a completed status is a closed session', async () => {
    const device = await oldDevice();
    const transfer = device.watch();
    device.server.completedAt = '2026-11-11T10:00:00.000Z';

    await expect(transfer.outcome).resolves.toBe('closed');
  });

  it('reports expiry and keeps polling through transient errors', async () => {
    const device = await oldDevice();
    const onPollError = vi.fn();
    let reads = 0;
    const realFetch = device.fetchImpl.getMockImplementation();
    device.fetchImpl.mockImplementation(async (url, init) => {
      if (url.includes('/device-transfer/sessions/') && ++reads === 1) throw new TypeError('network down');
      return realFetch(url, init);
    });
    const transfer = device.watch({ onPollError });
    device.server.expired = true;

    await expect(transfer.outcome).resolves.toBe('expired');
    expect(onPollError).toHaveBeenCalledTimes(1);
    expect(device.rejections).toEqual([]);
  });

  it('stops polling once cancelled', async () => {
    const device = await oldDevice();
    const transfer = device.watch();
    await vi.waitFor(() => expect(device.server.calls.length).toBeGreaterThan(0));
    transfer.cancel();

    await expect(transfer.outcome).resolves.toBe('cancelled');
    const seen = device.server.calls.length;
    await new Promise((resolve) => setTimeout(resolve, 20));
    expect(device.server.calls.length).toBeLessThanOrEqual(seen + 1);
    expect(transfer.approved).toBe(false);
  });

  describe('a failed approval', () => {
    async function claimedWithFailingApprove() {
      const device = await oldDevice();
      const onClaim = vi.fn();
      const transfer = device.watch({ onClaim });
      device.server.claimed = true;
      await vi.waitFor(() => expect(onClaim).toHaveBeenCalledTimes(1));
      const realFetch = device.fetchImpl.getMockImplementation();
      let failApprove = true;
      device.fetchImpl.mockImplementation(async (url, init) => {
        if (url.endsWith('/device-transfer/approve') && failApprove) {
          failApprove = false;
          return { ok: false, status: 503, text: async () => '{"message":"down"}' };
        }
        return realFetch(url, init);
      });
      await expect(transfer.approve()).rejects.toMatchObject({ status: 503 });
      return { device, transfer };
    }

    it('counts for nothing', async () => {
      const { device, transfer } = await claimedWithFailingApprove();
      expect(transfer.approved).toBe(false);
      device.server.deviceActive = false;

      await expect(transfer.outcome).resolves.toBe('session-ended');
    });

    it('can be retried', async () => {
      const { device, transfer } = await claimedWithFailingApprove();
      await expect(transfer.approve()).resolves.toBe(true);
      expect(transfer.approved).toBe(true);
      device.server.complete();

      await expect(transfer.outcome).resolves.toBe('completed');
    });
  });
});
