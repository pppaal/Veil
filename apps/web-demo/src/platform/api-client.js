// REST client for /v1 and the device-bound session lifecycle.
//
// A rejected access token is recovered by a refresh, then by a fresh
// challenge signed with the device key, then the request is retried once.
// When the server still answers 401 the session ends (tokens dropped) but the
// identity stays on the device. VEIL has no account recovery, so a wiped key
// is gone for good, and a transient 401 (JWT secret rotation, clock skew, a
// proxy or WAF, a buggy or hostile server) must never be able to cost the
// user their handle. Destroying the identity is a separate, explicit act.

export class ApiError extends Error {
  constructor(status, message, code) {
    super(message);
    this.name = 'ApiError';
    this.status = status;
    this.code = code;
  }
}

export class AuthError extends Error {
  constructor(reason) {
    super(reason === 'session_rejected'
      ? '서버가 이 기기의 세션을 거부했어요'
      : '로그인되어 있지 않아요');
    this.name = 'AuthError';
    this.reason = reason;
  }
}

// Statuses with which the auth endpoints refuse this device's credentials.
// Anything else (network failure, 5xx, 429) is transient and leaves the
// session alone.
const AUTH_REJECTION_STATUSES = new Set([400, 401, 403, 404]);

export const isAuthRejection = (error) => error instanceof ApiError && AUTH_REJECTION_STATUSES.has(error.status);

// 401 codes with which the API refuses a proof the request itself carries
// (a device-transfer approval's signature, a step-up challenge), not the
// bearer token: the session is fine, and recovering it would only send the
// same proof again and then end a working session.
const PROOF_REFUSAL_CODES = new Set(['invalid_device_signature', 'challenge_invalid']);
const isTokenRejection = (error) => error?.status === 401 && !PROOF_REFUSAL_CODES.has(error.code);

// The most the learned offset may move a disappearing-message expiry
// (expiryNow): the clock it is stamped and judged on follows the relay's,
// but a relay lying in its Date header shifts a sealed expiry by no more.
export const MAX_EXPIRY_CORRECTION_MS = 60 * 60 * 1000;

// now() -> this device's clock (ms).
export function createApiClient({ fetchImpl, baseUrl, tokenStore, onSessionRejected, now = Date.now }) {
  let recovery = null;
  let rejection = null;
  // Server time minus ours, from the HTTP Date header of the latest response
  // that carried one, refusals included (contract C-SPK): signed prekeys are
  // stamped with server time, which the directory checks to the minute.
  let clockOffsetMs = 0;

  function learnServerClock(response) {
    const serverDate = Date.parse(response.headers?.get?.('date') ?? '');
    if (Number.isFinite(serverDate)) clockOffsetMs = serverDate - now();
  }

  async function request(path, { method = 'GET', body, token } = {}) {
    const response = await fetchImpl(baseUrl + path, {
      method,
      headers: {
        'Content-Type': 'application/json',
        ...(token ? { Authorization: `Bearer ${token}` } : {}),
      },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    learnServerClock(response);
    const text = await response.text();
    const data = parseJson(text);
    if (!response.ok) {
      throw new ApiError(response.status, errorMessage(data, text, response.status), data?.code);
    }
    return data ?? {};
  }

  async function login(credentials) {
    const challenge = await request('/auth/challenge', {
      method: 'POST',
      body: { handle: credentials.handle, deviceId: credentials.deviceId },
    });
    const signature = await credentials.sign(challenge.challenge);
    const verified = await request('/auth/verify', {
      method: 'POST',
      body: { challengeId: challenge.challengeId, deviceId: credentials.deviceId, signature },
    });
    await tokenStore.saveTokens({
      accessToken: verified.accessToken,
      refreshToken: verified.refreshToken,
      userId: verified.userId,
    });
    return verified;
  }

  async function refreshTokens() {
    const refreshToken = tokenStore.getRefreshToken();
    if (!refreshToken) return null;
    try {
      const tokens = await request('/auth/refresh', { method: 'POST', body: { refreshToken } });
      await tokenStore.saveTokens({ accessToken: tokens.accessToken, refreshToken: tokens.refreshToken });
      return tokens.accessToken;
    } catch (error) {
      if (isAuthRejection(error)) return null;
      throw error;
    }
  }

  async function rechallenge() {
    const credentials = await tokenStore.getDeviceCredentials();
    if (!credentials) return null;
    try {
      return (await login(credentials)).accessToken;
    } catch (error) {
      if (isAuthRejection(error)) return null;
      throw error;
    }
  }

  // Single-flight: the server rotates refresh tokens on use, so two parallel
  // refreshes would invalidate each other.
  function recoverSession() {
    recovery ??= (async () => (await refreshTokens()) ?? (await rechallenge()))()
      .finally(() => { recovery = null; });
    return recovery;
  }

  async function rejectSession(rejectedToken) {
    // Another request already renewed or ended this session.
    if (rejection === null && tokenStore.getAccessToken() !== rejectedToken) return;
    rejection ??= (async () => {
      await tokenStore.clearTokens();
      onSessionRejected?.();
    })().finally(() => { rejection = null; });
    await rejection;
  }

  async function authedApi(path, options = {}) {
    const token = tokenStore.getAccessToken();
    if (!token) throw new AuthError('no_session');
    try {
      return await request(path, { ...options, token });
    } catch (error) {
      if (!isTokenRejection(error)) throw error;
    }
    const current = tokenStore.getAccessToken();
    // The session ended while this request was in flight. Recovering now
    // would quietly sign in again behind the restore screen.
    if (!current) throw new AuthError('no_session');
    const fresh = current !== token ? current : await recoverSession();
    if (fresh) {
      try {
        return await request(path, { ...options, token: fresh });
      } catch (error) {
        if (!isTokenRejection(error)) throw error;
      }
    }
    await rejectSession(fresh ?? token);
    throw new AuthError('session_rejected');
  }

  return {
    api: (path, options) => request(path, options),
    authedApi,
    login,
    // This device's clock corrected to the server's, as far as learned.
    serverNow: () => now() + clockOffsetMs,
    // The same with the correction clamped to MAX_EXPIRY_CORRECTION_MS: the
    // clock disappearing-message expiries are stamped and judged on
    // (src/core/expiry.js expiryNow).
    expiryNow: () => now() + Math.min(MAX_EXPIRY_CORRECTION_MS, Math.max(-MAX_EXPIRY_CORRECTION_MS, clockOffsetMs)),
  };
}

function parseJson(text) {
  if (!text) return null;
  try {
    return JSON.parse(text);
  } catch {
    return null;
  }
}

function errorMessage(data, text, status) {
  const message = data?.message;
  if (Array.isArray(message)) return message.join(', ');
  if (typeof message === 'string') return message;
  return text || `HTTP ${status}`;
}
