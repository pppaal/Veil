// The in-memory relay the browser tests run against (e2e/mock-server.mjs)
// must refuse what the real API refuses on the routes the demo uses, with
// the same status and error code, or a break between the demo and the API
// would pass there unnoticed. Each case below mirrors an API rule:
// KeysService.rotateSignedPrekey (contract C-SPK), PrekeysService.upload,
// FileAbuseReportDto and CreateUploadTicketDto under the global
// ValidationPipe ({ whitelist, forbidNonWhitelisted }), MessagesService.markRead,
// DeviceTransferService and SecretController.

import { spawn } from 'node:child_process';
import { webcrypto } from 'node:crypto';
import { fileURLToPath } from 'node:url';

import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import { encodeBase64Url } from '../src/core/base64url.js';
import { signBundle } from '../src/crypto/bundle.js';
import { generateIdentity, publishedKeys, signChallenge } from '../src/crypto/identity.js';
import { createKeySource } from '../src/crypto/keys.js';

const { subtle } = webcrypto;
const MINUTE_MS = 60 * 1000;
const PORT = 4900 + Math.floor(Math.random() * 90);
const BASE = `http://127.0.0.1:${PORT}`;
const MOCK = fileURLToPath(new URL('../e2e/mock-server.mjs', import.meta.url));

let relay;
let token;
let identity;
let handle;
let deviceId;

async function call(path, { method = 'GET', body, auth = true } = {}) {
  const response = await fetch(BASE + path, {
    method,
    headers: { 'Content-Type': 'application/json', ...(auth ? { Authorization: `Bearer ${token}` } : {}) },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  return { status: response.status, date: response.headers.get('date'), body: await response.json() };
}

async function signedPrekeyBundle({ id, createdAt, signer = identity.ik.privateKey }) {
  const pair = await createKeySource(webcrypto).x25519();
  return signBundle(subtle, signer, {
    ikx: identity.ikx.publicKey,
    ikxSig: identity.ikx.signature,
    spk: { id, publicKey: pair.publicKey, createdAt },
  });
}

beforeAll(async () => {
  relay = spawn(process.execPath, [MOCK], { env: { ...process.env, VEIL_MOCK_PORT: String(PORT) }, stdio: 'ignore' });
  for (let attempt = 0; ; attempt += 1) {
    try {
      if ((await fetch(`${BASE}/__test/health`)).ok) break;
    } catch {
      if (attempt > 100) throw new Error('mock relay did not start');
      await new Promise((resolve) => setTimeout(resolve, 50));
    }
  }
  identity = await generateIdentity(subtle);
  handle = `relay${PORT}`;
  const registered = await call('/v1/auth/register', {
    method: 'POST',
    auth: false,
    body: { handle, ...(await publishedKeys(subtle, identity)) },
  });
  deviceId = registered.body.deviceId;
  token = (await signIn(handle, deviceId, identity)).body.accessToken;
});

// The challenge's refusal, or the verify response.
async function signIn(who, device, keys) {
  const asked = await call('/v1/auth/challenge', { method: 'POST', auth: false, body: { handle: who, deviceId: device } });
  if (asked.status !== 200) return asked;
  const challenge = asked.body;
  return call('/v1/auth/verify', {
    method: 'POST',
    auth: false,
    body: { challengeId: challenge.challengeId, deviceId: device, signature: await signChallenge(subtle, keys.edPrivKey, challenge.challenge) },
  });
}

afterAll(() => {
  relay?.kill();
});

describe('the mock relay refuses what the API refuses', () => {
  it('serves a Date header the client corrects its clock by', async () => {
    const { date } = await call('/v1/prekeys/count');
    expect(Math.abs(Date.parse(date) - Date.now())).toBeLessThan(5_000);
  });

  it('checks a signed prekey as KeysService.rotateSignedPrekey does', async () => {
    const put = async (signedPrekeyBundle) => call('/v1/keys/signed-prekey', { method: 'PUT', body: { signedPrekeyBundle } });
    const now = Date.now();
    const outOfWindow = { status: 400, body: { code: 'signed_prekey_timestamp_out_of_window' } };
    expect(await put(await signedPrekeyBundle({ id: 2, createdAt: now - 61 * MINUTE_MS }))).toMatchObject(outOfWindow);
    expect(await put(await signedPrekeyBundle({ id: 2, createdAt: now + 11 * MINUTE_MS }))).toMatchObject(outOfWindow);
    const stranger = await generateIdentity(subtle);
    expect(await put(await signedPrekeyBundle({ id: 2, createdAt: now, signer: stranger.ik.privateKey })))
      .toMatchObject({ status: 400, body: { code: 'invalid_device_signature' } });
    expect(await put('not-a-bundle')).toMatchObject({ status: 400, body: { code: 'validation_failed' } });

    const accepted = await signedPrekeyBundle({ id: 2, createdAt: now - 59 * MINUTE_MS });
    expect(await put(accepted)).toMatchObject({ status: 200, body: { spkId: 2 } });
    expect(await put(accepted)).toMatchObject({
      status: 400,
      body: { code: 'validation_failed', message: 'spkId must increase with every rotation' },
    });
  });

  it('skips one-time prekey ids it holds and answers { uploaded, available }', async () => {
    const pair = await createKeySource(webcrypto).x25519();
    const prekeys = [{ keyId: 7, publicKey: encodeBase64Url(pair.publicKey) }];
    const upload = (batch) => call('/v1/prekeys', { method: 'POST', body: { prekeys: batch } });
    expect(await upload(prekeys)).toMatchObject({ status: 200, body: { uploaded: 1, available: 1 } });
    expect(await upload(prekeys)).toMatchObject({ status: 200, body: { uploaded: 0, available: 1 } });
    expect(await upload([])).toMatchObject({ status: 400 });
  });

  it('takes an abuse report only in the shape of FileAbuseReportDto', async () => {
    const ids = { reportedUserId: webcrypto.randomUUID(), conversationId: webcrypto.randomUUID(), messageId: webcrypto.randomUUID() };
    // What the web demo used to send.
    const legacy = await call('/v1/safety/reports', {
      method: 'POST',
      body: { targetUserId: ids.reportedUserId, relatedMessageId: ids.messageId, category: 'other', details: 'typed text' },
    });
    expect(legacy).toMatchObject({ status: 400, body: { code: 'validation_failed' } });
    for (const field of ['targetUserId', 'relatedMessageId', 'category', 'details']) {
      expect(legacy.body.message).toContain(`property ${field} should not exist`);
    }
    expect(await call('/v1/safety/reports', { method: 'POST', body: { ...ids, reason: 'rude' } })).toMatchObject({ status: 400 });
    expect(await call('/v1/safety/reports', { method: 'POST', body: { ...ids, reason: 'spam' } }))
      .toMatchObject({ status: 200, body: { reportId: expect.any(String) } });
  });

  it('takes only a random UUID as a proposed attachment id', async () => {
    const ticket = (attachmentId) => call('/v1/attachments/upload-ticket', {
      method: 'POST',
      body: { attachmentId, contentType: 'application/octet-stream', sizeBytes: 10, sha256: 'a'.repeat(64) },
    });
    for (const refused of ['attachment-1', 'a8098c1a-f86e-11da-bd1a-00112444be1e']) {
      expect(await ticket(refused)).toMatchObject({ status: 400, body: { code: 'validation_failed' } });
    }
    const attachmentId = webcrypto.randomUUID();
    expect(await ticket(attachmentId)).toMatchObject({ status: 200, body: { attachmentId } });
  });

  it('refuses a read receipt for a message the reader cannot see', async () => {
    expect(await call(`/v1/messages/${webcrypto.randomUUID()}/read`, { method: 'POST', body: {} }))
      .toMatchObject({ status: 404, body: { code: 'message_not_found' } });
  });

  it('keeps a one-time secret for a single read', async () => {
    const create = (body) => call('/v1/s', { method: 'POST', auth: false, body });
    expect(await create({ ciphertext: '' })).toMatchObject({ status: 400, body: { code: 'validation_failed' } });
    expect(await create({ ciphertext: 'sealed', ttlSeconds: 10 })).toMatchObject({ status: 400 });
    const { body: created } = await create({ ciphertext: 'sealed' });
    expect(await call('/v1/s/not-a-uuid', { auth: false })).toMatchObject({ status: 400 });
    expect(await call(`/v1/s/${created.id}`, { auth: false })).toMatchObject({ status: 200, body: { ciphertext: 'sealed' } });
    expect(await call(`/v1/s/${created.id}`, { auth: false })).toMatchObject({ status: 404 });
  });

  // The new device proves its keys at claim and at completion, the old one
  // approves in between, and completing revokes the old device.
  it('runs a device transfer as DeviceTransferService does', async () => {
    const init = (oldDeviceId) => call('/v1/device-transfer/init', { method: 'POST', body: { oldDeviceId } });
    expect(await init(webcrypto.randomUUID())).toMatchObject({ status: 403, body: { code: 'device_forbidden' } });
    const { body: session } = await init(deviceId);
    const { sessionId, transferToken } = session;
    const status = async () => (await call(`/v1/device-transfer/sessions/${sessionId}`)).body;
    expect(await status()).toMatchObject({ status: 'pending', pendingClaim: null });

    const fresh = await generateIdentity(subtle);
    const published = await publishedKeys(subtle, fresh);
    const claimBody = async (signer = fresh) => ({
      sessionId,
      transferToken,
      newDeviceName: 'web-test',
      platform: 'android',
      ...published,
      authProof: await signChallenge(subtle, signer.edPrivKey, `transfer-claim:${sessionId}:${transferToken}`),
    });
    const claim = async (body) => call('/v1/device-transfer/claim', { method: 'POST', auth: false, body });
    expect(await claim({ ...(await claimBody()), transferToken: 'wrong' })).toMatchObject({ status: 401, body: { code: 'transfer_token_invalid' } });
    expect(await claim(await claimBody(identity))).toMatchObject({ status: 401, body: { code: 'transfer_claim_invalid' } });
    const { body: claimed } = await claim(await claimBody());
    expect(claimed.claimantFingerprint).toMatch(/^([0-9a-f]{4} ){15}[0-9a-f]{4}$/);
    expect(await status()).toMatchObject({ status: 'claimed', pendingClaim: { claimId: claimed.claimId, approvedAt: null } });

    const complete = async (signer = fresh) => call('/v1/device-transfer/complete', {
      method: 'POST',
      auth: false,
      body: {
        sessionId,
        transferToken,
        claimId: claimed.claimId,
        authProof: await signChallenge(subtle, signer.edPrivKey, `transfer-complete:${sessionId}:${claimed.claimId}:${transferToken}`),
      },
    });
    expect(await complete()).toMatchObject({ status: 403, body: { code: 'transfer_approval_required' } });
    const approve = (claimId) => call('/v1/device-transfer/approve', { method: 'POST', body: { sessionId, claimId } });
    expect(await approve(webcrypto.randomUUID())).toMatchObject({ status: 403, body: { code: 'transfer_claim_required' } });
    expect(await approve(claimed.claimId)).toMatchObject({ status: 200, body: { approved: true } });
    expect(await complete(identity)).toMatchObject({ status: 401, body: { code: 'transfer_completion_invalid' } });
    const { status: completedStatus, body: completion } = await complete();
    expect(completedStatus).toBe(200);
    expect(completion).toMatchObject({ handle, revokedDeviceId: deviceId });

    // The old device is out: its token, and a fresh sign-in, are refused.
    expect(await call('/v1/prekeys/count')).toMatchObject({ status: 401 });
    expect(await signIn(handle, deviceId, identity)).toMatchObject({ status: 404, body: { code: 'active_device_not_found' } });
    const signedIn = await signIn(handle, completion.newDeviceId, fresh);
    expect(signedIn).toMatchObject({ status: 200, body: { deviceId: completion.newDeviceId } });
    token = signedIn.body.accessToken;
    expect(await complete()).toMatchObject({ status: 403, body: { code: 'transfer_session_inactive' } });
  });
});
