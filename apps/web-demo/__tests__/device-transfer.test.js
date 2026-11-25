import { describe, expect, it, vi } from 'vitest';
import { webcrypto } from 'node:crypto';

import { decodeBase64Url } from '../src/core/base64url.js';
import { generateIdentity, signChallenge } from '../src/crypto/identity.js';
import { ED25519 } from '../src/crypto/keys.js';
import { createDeviceTransfer } from '../src/app/services/device-transfer.js';
import { approvalChallenge, storeTransferredIdentity, watchOldDeviceTransfer } from '../src/features/device-transfer.js';
import { ApiError, createApiClient } from '../src/platform/api-client.js';
import { createSessionStore } from '../src/platform/session-store.js';
import { wipeInPlace } from '../src/platform/wipe.js';
import { memorySessionRepo } from './support/session-repo.js';

const { subtle } = webcrypto;
const SESSION_ID = '3b9f6c1e-2a4d-4e8f-9b0a-1c2d3e4f5a6b';
const CLAIM = { claimId: 'claim-1', claimantFingerprint: 'ab12 cd34', newDeviceName: 'web', platform: 'android' };

// As Ed25519DeviceAuthVerifier: an Ed25519 signature by the raw auth key
// over the challenge text, base64url.
async function signedBy(authPublicKey, challenge, proof) {
  try {
    const key = await subtle.importKey('raw', decodeBase64Url(authPublicKey), ED25519, false, ['verify']);
    return await subtle.verify(ED25519, key, decodeBase64Url(proof), new TextEncoder().encode(challenge));
  } catch {
    return false;
  }
}

// The API as the old device sees it. complete() is the new device's
// /device-transfer/complete: like DeviceTransferService.complete it marks
// the session completed and revokes the old device in one step, after which
// the JWT guard, /auth/refresh and /auth/challenge all refuse the old device.
// An approval is taken, as DeviceTransferService.approve takes it, only with
// the old device's signature by oldDeviceAuthKey over the claim and its
// fingerprint; anything else is a 401 invalid_device_signature.
function fakeTransferApi({ oldDeviceAuthKey }) {
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
    '/device-transfer/approve': guarded(async ({ body }) => {
      expect(Object.keys(body).sort()).toEqual(['approvalProof', 'claimId', 'sessionId']);
      expect(body).toMatchObject({ sessionId: SESSION_ID, claimId: CLAIM.claimId });
      const challenge = `transfer-approve:${SESSION_ID}:${CLAIM.claimId}:${CLAIM.claimantFingerprint}`;
      if (!body.approvalProof || !(await signedBy(oldDeviceAuthKey, challenge, body.approvalProof))) {
        return [401, { code: 'invalid_device_signature', message: 'Approval signature is invalid' }];
      }
      server.approvedClaimId = body.claimId;
      return [200, { sessionId: SESSION_ID, claimId: body.claimId, approvedAt: '2026-11-11T09:59:00.000Z' }];
    }),
  };
  const fetchImpl = vi.fn(async (url, init) => {
    const path = url.replace('/v1', '');
    const body = init.body ? JSON.parse(init.body) : undefined;
    server.calls.push(path);
    const route = routes[path];
    const [code, payload] = route ? await route({ body }) : [404, { message: 'no route' }];
    return { ok: code >= 200 && code < 300, status: code, text: async () => JSON.stringify(payload) };
  });
  return { server, fetchImpl };
}

// The old device: a signed-in session store and an API client whose
// onSessionRejected asks the transfer first, the way app.js wires it.
async function oldDevice() {
  const identity = await generateIdentity(subtle);
  const api = fakeTransferApi({ oldDeviceAuthKey: identity.edPubB64u });
  const repo = memorySessionRepo({
    handle: 'alice',
    userId: 'user-1',
    deviceId: 'device-old',
    ...identity,
    accessToken: 'access-1',
    refreshToken: 'refresh-1',
  });
  const store = createSessionStore({ repo, subtle });
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
      // As app.js signs it: with the auth key this device logs in with.
      signApproval: async (challenge) => (await store.getDeviceCredentials()).sign(challenge),
      sleep: () => new Promise((resolve) => setTimeout(resolve, 0)),
      ...options,
    });
    return transfer;
  };
  return { ...api, store, rejections, watch, stored: repo.peek };
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

  it('signs the approval over the claim and the fingerprint the user compared', async () => {
    const device = await oldDevice();
    const signed = [];
    const credentials = await device.store.getDeviceCredentials();
    const transfer = device.watch({
      signApproval: (challenge) => {
        signed.push(challenge);
        return credentials.sign(challenge);
      },
      onClaim: () => transfer.approve(),
    });
    device.server.claimed = true;

    await vi.waitFor(() => expect(device.server.approvedClaimId).toBe(CLAIM.claimId));
    expect(signed).toEqual([`transfer-approve:${SESSION_ID}:${CLAIM.claimId}:${CLAIM.claimantFingerprint}`]);
    expect(approvalChallenge(SESSION_ID, CLAIM)).toBe(signed[0]);
    transfer.cancel();
  });

  it('an approval signed by another key is refused and keeps the session', async () => {
    const device = await oldDevice();
    const stranger = await generateIdentity(subtle);
    const onClaim = vi.fn();
    const transfer = device.watch({
      signApproval: (challenge) => signChallenge(subtle, stranger.edPrivKey, challenge),
      onClaim,
    });
    device.server.claimed = true;
    await vi.waitFor(() => expect(onClaim).toHaveBeenCalledTimes(1));

    await expect(transfer.approve()).rejects.toMatchObject({ status: 401, code: 'invalid_device_signature' });
    expect(transfer.approved).toBe(false);
    expect(device.server.approvedClaimId).toBeNull();
    expect(device.rejections).toEqual([]);
    expect(device.store.getAccessToken()).toBe('access-1');
    transfer.cancel();
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

// The new device's /device-transfer/complete (contract C-TRANSFER-RETRY).
// The relay answers an identical retry of a completion that went through
// with that completion, so a request that got no answer, or a 5xx, is sent
// again as it was; only "not approved yet" is polled; any other refusal
// stops, leaving the keys with the caller.
describe('awaitCompletion', () => {
  const TRANSFER_SESSION = '0d3c7a52-5f1e-4c8b-9a6d-2e7f8b9c0a1d';
  const CLAIM_ID = '7e1f2a3b-4c5d-4e6f-8a9b-0c1d2e3f4a5b';
  const COMPLETION = { sessionId: TRANSFER_SESSION, claimId: CLAIM_ID, newDeviceId: 'device-new', handle: 'alice' };
  const notApproved = () => new ApiError(403, 'Old device approval is required before completion', 'transfer_approval_required');

  // answers: what each /complete call gets, in order: a response body, or
  // an error to throw.
  async function newDevice(answers) {
    const keys = await generateIdentity(subtle);
    const requests = [];
    const stack = {
      api: vi.fn(async (path, { body }) => {
        requests.push({ path, body });
        const answer = answers.shift();
        if (answer instanceof Error) throw answer;
        if (answer === undefined) throw new Error('no more answers');
        return answer;
      }),
    };
    const transfer = createDeviceTransfer({ store: {}, stack, session: {}, sleep: async () => {} });
    const claim = { sessionId: TRANSFER_SESSION, transferToken: 'token-1', claimId: CLAIM_ID, keys };
    return { transfer, requests, claim };
  }

  async function expectOneProofThroughout({ requests, claim }) {
    const bodies = requests.map((request) => JSON.stringify(request.body));
    expect(new Set(bodies).size).toBe(1);
    expect(requests.every((request) => request.path === '/device-transfer/complete')).toBe(true);
    const { body } = requests[0];
    expect(body).toMatchObject({ sessionId: TRANSFER_SESSION, transferToken: 'token-1', claimId: CLAIM_ID });
    const challenge = `transfer-complete:${TRANSFER_SESSION}:${CLAIM_ID}:token-1`;
    expect(await signedBy(claim.keys.edPubB64u, challenge, body.authProof)).toBe(true);
  }

  it('polls while the old device has not approved, then completes', async () => {
    const device = await newDevice([notApproved(), notApproved(), COMPLETION]);
    const onWaiting = vi.fn();

    await expect(device.transfer.awaitCompletion(device.claim, { waiting: () => true, onWaiting })).resolves.toEqual(COMPLETION);
    expect(onWaiting).toHaveBeenCalledTimes(2);
    await expectOneProofThroughout(device);
  });

  it('sends the same request again after a network failure or a 5xx', async () => {
    const device = await newDevice([
      new TypeError('Failed to fetch'),
      new ApiError(502, 'Bad Gateway'),
      notApproved(),
      new ApiError(500, 'oops'),
      COMPLETION,
    ]);
    const onRetrying = vi.fn();

    await expect(device.transfer.awaitCompletion(device.claim, { waiting: () => true, onWaiting: () => {}, onRetrying }))
      .resolves.toEqual(COMPLETION);
    expect(onRetrying).toHaveBeenCalledTimes(3);
    expect(device.requests).toHaveLength(5);
    await expectOneProofThroughout(device);
  });

  // The completion may have gone through on the request that got no answer:
  // the keys are then the identity's only copy, so the caller giving up
  // waiting for the approval does not end the retries.
  it('keeps retrying a request that got no answer after waiting() turned false', async () => {
    const device = await newDevice([new TypeError('Failed to fetch'), new ApiError(503, 'unavailable'), COMPLETION]);
    let waiting = true;
    const onRetrying = vi.fn(() => { waiting = false; });

    await expect(device.transfer.awaitCompletion(device.claim, { waiting: () => waiting, onWaiting: () => {}, onRetrying }))
      .resolves.toEqual(COMPLETION);
    expect(device.requests).toHaveLength(3);
  });

  it('stops once waiting() is false and the relay says it is not approved', async () => {
    const device = await newDevice([new TypeError('Failed to fetch'), notApproved()]);
    let waiting = true;

    await expect(device.transfer.awaitCompletion(device.claim, {
      waiting: () => waiting,
      onWaiting: () => {},
      onRetrying: () => { waiting = false; },
    })).resolves.toBeNull();
    expect(device.requests).toHaveLength(2);
  });

  it.each([
    [403, 'transfer_session_inactive'],
    [403, 'transfer_claim_required'],
    [401, 'transfer_completion_invalid'],
    [401, 'transfer_token_invalid'],
    [404, 'transfer_session_not_found'],
    [429, undefined],
  ])('stops on a %s %s without sending it again', async (status, code) => {
    const device = await newDevice([new ApiError(status, 'refused', code), COMPLETION]);
    const onWaiting = vi.fn();

    await expect(device.transfer.awaitCompletion(device.claim, { waiting: () => true, onWaiting }))
      .rejects.toMatchObject({ status, code });
    expect(device.requests).toHaveLength(1);
    expect(onWaiting).not.toHaveBeenCalled();
  });
});
