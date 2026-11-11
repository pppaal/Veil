import { describe, expect, it, vi } from 'vitest';
import { webcrypto } from 'node:crypto';

import { generateIdentity } from '../src/crypto/identity.js';
import { storeTransferredIdentity, watchOldDeviceTransfer } from '../src/features/device-transfer.js';
import { createApiClient } from '../src/platform/api-client.js';
import { createSessionStore } from '../src/platform/session-store.js';
import { wipeInPlace } from '../src/platform/wipe.js';

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
    expect(device.stored().ik.privateKey).toBeDefined();
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

describe('storeTransferredIdentity', () => {
  const COMPLETION = { handle: 'bob', newDeviceId: 'device-new', revokedDeviceId: 'device-bob-old' };

  // A browser that already holds another identity: its session record and
  // the data that identity left in the other stores and in localStorage.
  async function browserWithIdentity() {
    const database = new Map([
      ['session', { handle: 'alice', deviceId: 'device-alice', ...(await generateIdentity(subtle)) }],
      ['conversations', ['c-1']],
      ['outbound', ['queued-1']],
    ]);
    const repo = {
      get: async () => database.get('session'),
      put: vi.fn(async (record) => { database.set('session', record); }),
    };
    const sessionStore = createSessionStore({ repo, subtle });
    await sessionStore.load();
    const localStorage = new Map([['veil-demo-muted-convs-v1', '["c-1"]']]);
    // The app's clearReplacedIdentity with this browser's storage behind it.
    const clearReplacedIdentity = vi.fn(() => wipeInPlace({
      clearDatabase: async () => {
        for (const store of database.keys()) if (store !== 'session') database.set(store, []);
      },
      localStorage: {
        get length() { return localStorage.size; },
        key: (i) => [...localStorage.keys()][i] ?? null,
        removeItem: (key) => { localStorage.delete(key); },
      },
      sessionStorage: null,
      // Cache Storage access is refused in some privacy modes.
      caches: { keys: async () => { throw new DOMException('access denied', 'SecurityError'); } },
    }));
    return { database, repo, sessionStore, localStorage, clearReplacedIdentity };
  }

  it('a failing cleanup step still ends with the new keys stored', async () => {
    const browser = await browserWithIdentity();
    const keys = await generateIdentity(subtle);

    const { cleanupError } = await storeTransferredIdentity({
      completion: COMPLETION,
      keys,
      sessionStore: browser.sessionStore,
      clearReplacedIdentity: browser.clearReplacedIdentity,
    });

    expect(cleanupError).toBeInstanceOf(AggregateError);
    expect(cleanupError.errors.map((e) => e.name)).toEqual(['SecurityError']);
    const stored = browser.database.get('session');
    expect(stored).toMatchObject({ handle: 'bob', deviceId: 'device-new', userId: null, accessToken: null });
    expect(stored.edPrivKey).toBe(keys.edPrivKey);
    expect(stored.xPrivKey).toBe(keys.xPrivKey);
    expect(browser.sessionStore.current()).toBe(stored);
    // The steps that could run did: nothing of the replaced identity is left.
    expect(browser.database.get('conversations')).toEqual([]);
    expect(browser.database.get('outbound')).toEqual([]);
    expect(browser.localStorage.size).toBe(0);
  });

  it('stores the keys before cleanup starts, so cleanup that never finishes cannot hold them back', async () => {
    const browser = await browserWithIdentity();
    const keys = await generateIdentity(subtle);
    let storedWhenCleanupStarted = null;

    // As when another tab holds up a database delete: the step never settles.
    storeTransferredIdentity({
      completion: COMPLETION,
      keys,
      sessionStore: browser.sessionStore,
      clearReplacedIdentity: () => {
        storedWhenCleanupStarted = browser.database.get('session');
        return new Promise(() => {});
      },
    });

    await vi.waitFor(() => expect(storedWhenCleanupStarted).not.toBeNull());
    expect(storedWhenCleanupStarted.handle).toBe('bob');
    expect(storedWhenCleanupStarted.edPrivKey).toBe(keys.edPrivKey);
  });

  it('a failed save throws with nothing cleared, and the same keys can be saved again', async () => {
    const browser = await browserWithIdentity();
    const replaced = browser.database.get('session');
    const keys = await generateIdentity(subtle);
    browser.repo.put.mockRejectedValueOnce(new DOMException('quota exceeded', 'QuotaExceededError'));
    const store = () => storeTransferredIdentity({
      completion: COMPLETION,
      keys,
      sessionStore: browser.sessionStore,
      clearReplacedIdentity: browser.clearReplacedIdentity,
    });

    await expect(store()).rejects.toThrow('quota exceeded');
    expect(browser.clearReplacedIdentity).not.toHaveBeenCalled();
    expect(browser.database.get('session')).toBe(replaced);
    expect(browser.sessionStore.current().handle).toBe('alice');
    expect(browser.database.get('conversations')).toEqual(['c-1']);

    // The retry the app offers: the keys it kept, saved again.
    await expect(store()).resolves.toMatchObject({ cleanupError: expect.any(AggregateError) });
    expect(browser.database.get('session').edPrivKey).toBe(keys.edPrivKey);
    expect(browser.clearReplacedIdentity).toHaveBeenCalledTimes(1);
  });

  it('clears nothing when no identity was stored here', async () => {
    let stored = null;
    const sessionStore = createSessionStore({ repo: { get: async () => stored, put: async (r) => { stored = r; } }, subtle });
    const keys = await generateIdentity(subtle);

    await expect(storeTransferredIdentity({ completion: COMPLETION, keys, sessionStore }))
      .resolves.toEqual({ cleanupError: null });
    expect(stored).toMatchObject({ handle: 'bob', deviceId: 'device-new' });
  });
});
