import { describe, expect, it, vi } from 'vitest';
import { webcrypto } from 'node:crypto';

import { decodeBase64Url } from '../src/core/base64url.js';
import { generateIdentity } from '../src/crypto/identity.js';
import { ApiError, AuthError, createApiClient, isAuthRejection } from '../src/platform/api-client.js';
import { createSessionStore } from '../src/platform/session-store.js';
import { memorySessionRepo } from './support/session-repo.js';

const { subtle } = webcrypto;

// delete is there to show that nothing ever deletes the record.
const memoryRepo = (initial) => ({ ...memorySessionRepo(initial), delete: vi.fn() });

async function signedInStore() {
  const identity = await generateIdentity(subtle);
  const repo = memoryRepo({
    handle: 'alice',
    userId: 'user-1',
    deviceId: 'device-1',
    ...identity,
    accessToken: 'access-old',
    refreshToken: 'refresh-old',
  });
  const store = createSessionStore({ repo, subtle });
  await store.load();
  return { repo, store, identity };
}

function jsonResponse(status, body) {
  return { ok: status >= 200 && status < 300, status, statusText: '', text: async () => JSON.stringify(body) };
}

// fetch double that routes by path and records every call.
function fakeFetch(routes) {
  const calls = [];
  const fetchImpl = vi.fn(async (url, init) => {
    const path = url.replace('/v1', '');
    const token = init.headers.Authorization?.replace('Bearer ', '') ?? null;
    const body = init.body ? JSON.parse(init.body) : undefined;
    calls.push({ path, token, body });
    const route = routes[path] ?? routes['*'];
    const [status, payload] = await route({ token, body });
    return jsonResponse(status, payload);
  });
  return { fetchImpl, calls, count: (path) => calls.filter((c) => c.path === path).length };
}

describe('createApiClient session lifecycle', () => {
  it('401 everywhere ends session without touching identity', async () => {
    const { repo, store, identity } = await signedInStore();
    const http = fakeFetch({ '*': () => [401, { code: 'unauthorized', message: 'nope' }] });
    const onSessionRejected = vi.fn();
    const client = createApiClient({ fetchImpl: http.fetchImpl, baseUrl: '/v1', tokenStore: store, onSessionRejected });

    const results = await Promise.allSettled([
      client.authedApi('/conversations'),
      client.authedApi('/conversations/c1/messages'),
      client.authedApi('/messages/m1/read', { method: 'POST', body: {} }),
    ]);

    for (const result of results) {
      expect(result.status).toBe('rejected');
      expect(result.reason).toBeInstanceOf(AuthError);
      expect(result.reason.reason).toBe('session_rejected');
    }
    expect(onSessionRejected).toHaveBeenCalledTimes(1);
    // Recovery was attempted: refresh, then a challenge signed with the device key.
    expect(http.count('/auth/refresh')).toBe(1);
    expect(http.count('/auth/challenge')).toBe(1);

    const stored = repo.peek();
    expect(repo.delete).not.toHaveBeenCalled();
    expect(stored.accessToken).toBeNull();
    expect(stored.refreshToken).toBeNull();
    expect(stored.handle).toBe('alice');
    expect(stored.deviceId).toBe('device-1');
    expect(stored.edPrivKey).toBe(identity.edPrivKey);
    expect(stored.xPrivKey).toBe(identity.xPrivKey);
    expect(stored.edPubB64u).toBe(identity.edPubB64u);
    expect(stored.xPubB64u).toBe(identity.xPubB64u);

    await expect(client.authedApi('/conversations')).rejects.toMatchObject({ reason: 'no_session' });
    expect(onSessionRejected).toHaveBeenCalledTimes(1);
  });

  it('concurrent 401s refresh once', async () => {
    const { store } = await signedInStore();
    const http = fakeFetch({
      '/auth/refresh': async ({ body }) => {
        await new Promise((resolve) => setTimeout(resolve, 5));
        return body.refreshToken === 'refresh-old'
          ? [200, { accessToken: 'access-new', refreshToken: 'refresh-new' }]
          : [401, { message: 'refresh token reused' }];
      },
      '*': ({ token }) => (token === 'access-new' ? [200, { ok: true }] : [401, { message: 'expired' }]),
    });
    const onSessionRejected = vi.fn();
    const client = createApiClient({ fetchImpl: http.fetchImpl, baseUrl: '/v1', tokenStore: store, onSessionRejected });

    const results = await Promise.all(Array.from({ length: 6 }, (_, i) => client.authedApi(`/r/${i}`)));

    expect(results).toEqual(Array.from({ length: 6 }, () => ({ ok: true })));
    expect(http.count('/auth/refresh')).toBe(1);
    expect(http.count('/auth/challenge')).toBe(0);
    expect(store.getAccessToken()).toBe('access-new');
    expect(store.getRefreshToken()).toBe('refresh-new');
    // A refresh names no user and leaves the recorded one alone.
    expect(store.current().userId).toBe('user-1');
    expect(onSessionRejected).not.toHaveBeenCalled();
  });

  it('a record without a userId gets it from the next successful login', async () => {
    // A transferred device's record is saved before its first login. When
    // that login fails, the record must not stay without a userId: the app
    // could not tell the peer from itself and would seal to its own key.
    const identity = await generateIdentity(subtle);
    const repo = memoryRepo({
      handle: 'alice',
      userId: null,
      deviceId: 'device-2',
      ...identity,
      accessToken: null,
      refreshToken: null,
    });
    const store = createSessionStore({ repo, subtle });
    await store.load();
    let challenges = 0;
    const http = fakeFetch({
      '/auth/challenge': () => (++challenges === 1
        ? [503, { message: 'unavailable' }]
        : [200, { challengeId: 'ch-2', challenge: 'sign-me' }]),
      '/auth/verify': () => [200, { accessToken: 'access-2', refreshToken: 'refresh-2', deviceId: 'device-2', userId: 'user-1' }],
    });
    const client = createApiClient({ fetchImpl: http.fetchImpl, baseUrl: '/v1', tokenStore: store });

    await expect(client.login(await store.getDeviceCredentials())).rejects.toMatchObject({ status: 503 });
    expect(repo.peek().userId).toBeNull();

    await client.login(await store.getDeviceCredentials());
    expect(store.current().userId).toBe('user-1');
    const reloaded = createSessionStore({ repo, subtle });
    await reloaded.load();
    expect(reloaded.current()).toMatchObject({ userId: 'user-1', accessToken: 'access-2', edPrivKey: identity.edPrivKey });
  });

  it('a 401 that lands after the session ended does not sign in again', async () => {
    const { store } = await signedInStore();
    let releaseSlow;
    const slowGate = new Promise((resolve) => { releaseSlow = resolve; });
    let challenges = 0;
    const byToken = ({ token }) => (token === 'revived' ? [200, { ok: true }] : [401, {}]);
    const http = fakeFetch({
      '/slow': async (request) => {
        await slowGate;
        return byToken(request);
      },
      '/auth/refresh': () => [401, {}],
      // The first challenge is turned down; a second one would be accepted.
      '/auth/challenge': () => (++challenges === 1 ? [401, {}] : [200, { challengeId: 'ch', challenge: 'c' }]),
      '/auth/verify': () => [200, { accessToken: 'revived', refreshToken: 'revived' }],
      '*': byToken,
    });
    const onSessionRejected = vi.fn();
    const client = createApiClient({ fetchImpl: http.fetchImpl, baseUrl: '/v1', tokenStore: store, onSessionRejected });

    const slow = client.authedApi('/slow').catch((error) => error);
    await expect(client.authedApi('/fast')).rejects.toMatchObject({ reason: 'session_rejected' });
    releaseSlow();

    const error = await slow;
    expect(error).toBeInstanceOf(AuthError);
    expect(error.reason).toBe('no_session');
    expect(http.count('/auth/challenge')).toBe(1);
    expect(store.getAccessToken()).toBeNull();
    expect(store.getRefreshToken()).toBeNull();
    expect(onSessionRejected).toHaveBeenCalledTimes(1);
  });

  it('falls back to a challenge signed with the stored device key', async () => {
    const { store, identity } = await signedInStore();
    let signature = null;
    const http = fakeFetch({
      '/auth/refresh': () => [401, { message: 'refresh token invalid' }],
      '/auth/challenge': ({ body }) => {
        expect(body).toEqual({ handle: 'alice', deviceId: 'device-1' });
        return [200, { challengeId: 'ch-1', challenge: 'sign-me' }];
      },
      '/auth/verify': ({ body }) => {
        signature = body.signature;
        return [200, { accessToken: 'access-2', refreshToken: 'refresh-2', userId: 'user-1' }];
      },
      '*': ({ token }) => (token === 'access-2' ? [200, { items: [] }] : [401, {}]),
    });
    const client = createApiClient({ fetchImpl: http.fetchImpl, baseUrl: '/v1', tokenStore: store });

    await expect(client.authedApi('/conversations')).resolves.toEqual({ items: [] });
    const publicKey = await subtle.importKey('raw', decodeBase64Url(identity.edPubB64u), { name: 'Ed25519' }, false, ['verify']);
    expect(await subtle.verify({ name: 'Ed25519' }, publicKey, decodeBase64Url(signature), new TextEncoder().encode('sign-me')))
      .toBe(true);
    expect(store.getAccessToken()).toBe('access-2');
  });

  it('a transient failure during recovery keeps the session', async () => {
    const { store } = await signedInStore();
    const http = fakeFetch({
      '/auth/refresh': () => [503, { message: 'unavailable' }],
      '*': () => [401, {}],
    });
    const onSessionRejected = vi.fn();
    const client = createApiClient({ fetchImpl: http.fetchImpl, baseUrl: '/v1', tokenStore: store, onSessionRejected });

    await expect(client.authedApi('/conversations')).rejects.toMatchObject({ status: 503 });
    expect(onSessionRejected).not.toHaveBeenCalled();
    expect(store.getAccessToken()).toBe('access-old');
    expect(store.getRefreshToken()).toBe('refresh-old');
  });

  it('non-401 errors pass through untouched', async () => {
    const { store } = await signedInStore();
    const http = fakeFetch({ '*': () => [422, { code: 'validation_failed', message: ['a', 'b'] }] });
    const client = createApiClient({ fetchImpl: http.fetchImpl, baseUrl: '/v1', tokenStore: store });

    const error = await client.authedApi('/messages', { method: 'POST', body: {} }).catch((e) => e);
    expect(error).toBeInstanceOf(ApiError);
    expect(error).toMatchObject({ status: 422, code: 'validation_failed', message: 'a, b' });
    expect(http.count('/auth/refresh')).toBe(0);
  });

  it('classifies auth rejections', () => {
    expect(isAuthRejection(new ApiError(404, 'device gone'))).toBe(true);
    expect(isAuthRejection(new ApiError(401, 'bad signature'))).toBe(true);
    expect(isAuthRejection(new ApiError(503, 'down'))).toBe(false);
    expect(isAuthRejection(new TypeError('network'))).toBe(false);
  });
});

// Contract C-SPK: the server's clock, learned from the Date header of every
// response that carries a parsable one, refusals included.
describe('createApiClient server clock', () => {
  const LOCAL = Date.parse('2026-11-12T09:00:00Z');
  const responding = (answers) => {
    const queue = [...answers];
    return vi.fn(async () => {
      const [status, date] = queue.shift();
      return {
        ...jsonResponse(status, status < 400 ? {} : { code: 'signed_prekey_timestamp_out_of_window', message: 'window' }),
        headers: new Headers(date === null ? {} : { date }),
      };
    });
  };

  it('corrects this device clock by the offset of the latest response', async () => {
    const fetchImpl = responding([
      [200, null],
      [200, 'Thu, 12 Nov 2026 09:20:00 GMT'],
      [400, 'Thu, 12 Nov 2026 08:00:00 GMT'],
      [200, 'not a date'],
    ]);
    const client = createApiClient({ fetchImpl, baseUrl: '/v1', tokenStore: {}, now: () => LOCAL });
    await client.api('/health');
    expect(client.serverNow()).toBe(LOCAL);
    await client.api('/health');
    expect(client.serverNow()).toBe(LOCAL + 20 * 60 * 1000);
    await expect(client.api('/keys/signed-prekey', { method: 'PUT', body: {} })).rejects.toMatchObject({ status: 400 });
    expect(client.serverNow()).toBe(LOCAL - 60 * 60 * 1000);
    // An unreadable header leaves the last offset in place.
    await client.api('/health');
    expect(client.serverNow()).toBe(LOCAL - 60 * 60 * 1000);
  });
});
