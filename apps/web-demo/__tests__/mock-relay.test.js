// The in-memory relay the browser tests run against (e2e/mock-server.mjs)
// must refuse what the real API refuses on the routes the demo uses, with
// the same status and error code, or a break between the demo and the API
// would pass there unnoticed. Each case below mirrors an API rule:
// KeysService.rotateSignedPrekey (contract C-SPK), PrekeysService.upload,
// FileAbuseReportDto and CreateUploadTicketDto under the global
// ValidationPipe ({ whitelist, forbidNonWhitelisted }).

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
  const handle = `relay${PORT}`;
  const registered = await call('/v1/auth/register', {
    method: 'POST',
    auth: false,
    body: { handle, ...(await publishedKeys(subtle, identity)) },
  });
  const { body: challenge } = await call('/v1/auth/challenge', {
    method: 'POST',
    auth: false,
    body: { handle, deviceId: registered.body.deviceId },
  });
  const { body: tokens } = await call('/v1/auth/verify', {
    method: 'POST',
    auth: false,
    body: {
      challengeId: challenge.challengeId,
      deviceId: registered.body.deviceId,
      signature: await signChallenge(subtle, identity.edPrivKey, challenge.challenge),
    },
  });
  token = tokens.accessToken;
});

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
});
