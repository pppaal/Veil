// The prekey lifecycle against the directory: one-time prekeys topped up in
// batches, the signed prekey rotated weekly and kept for its grace period,
// stamped and aged on the server's clock (contract C-SPK).

import { describe, expect, it, vi } from 'vitest';
import { webcrypto } from 'node:crypto';

import { decodeBase64Url } from '../src/core/base64url.js';
import { BundleError, verifyBundle } from '../src/crypto/bundle.js';
import { generateIdentity } from '../src/crypto/identity.js';
import { createKeySource } from '../src/crypto/keys.js';
import {
  createLocalKeyring,
  maintainPrekeys,
  ONE_TIME_PREKEY_BATCH,
  PrekeyUnavailableError,
  SIGNED_PREKEY_GRACE_MS,
  SIGNED_PREKEY_RESEND_MS,
  SIGNED_PREKEY_ROTATION_MS,
} from '../src/crypto/prekeys.js';
import { NO_ONE_TIME_PREKEY_ID } from '../src/crypto/x3dh.js';
import { createApiClient } from '../src/platform/api-client.js';
import { createMemoryKv } from '../src/platform/kv.js';

const { subtle } = webcrypto;
const MINUTE_MS = 60 * 1000;
const DAY_MS = 24 * 60 * MINUTE_MS;
const START = Date.parse('2026-11-11T09:00:00Z');

// The key directory as the API runs it for one device, on its own clock:
// PUT /keys/signed-prekey checks what KeysService.rotateSignedPrekey checks
// (signature, the spkTs window of an hour back and 10 minutes ahead, an
// increasing spkId), POST /prekeys skips ids it holds. handle() answers
// [status, body].
function fakeDirectory(identityKey, { available, failRotation, failUploads, uploadFailure = 503 }) {
  const directory = {
    now: START,
    available,
    spkId: 1,
    bundles: [],
    attempts: [],
    uploads: [],
    failRotation,
    failUploads,
  };
  const refusal = (code, message) => [400, { code, message }];
  directory.handle = async (path, { method = 'GET', body } = {}) => {
    if (path === '/prekeys/count') return [200, { available: directory.available }];
    if (path === '/prekeys' && method === 'POST') {
      if (directory.failUploads > 0) {
        directory.failUploads -= 1;
        return [uploadFailure, { code: 'unavailable', message: 'unavailable' }];
      }
      const held = new Set(directory.uploads.map((prekey) => prekey.keyId));
      const fresh = body.prekeys.filter((prekey) => !held.has(prekey.keyId));
      directory.uploads.push(...fresh);
      directory.available += fresh.length;
      return [200, { uploaded: fresh.length, available: directory.available }];
    }
    if (path === '/keys/signed-prekey' && method === 'PUT') {
      directory.attempts.push(body.signedPrekeyBundle);
      if (directory.failRotation) return [503, { code: 'unavailable', message: 'unavailable' }];
      let bundle;
      try {
        bundle = await verifyBundle(subtle, body.signedPrekeyBundle, identityKey, { nowMs: directory.now });
      } catch (error) {
        const outOfWindow = error instanceof BundleError && ['stale', 'future'].includes(error.reason);
        if (!outOfWindow) return refusal('invalid_device_signature', 'not signed by the device identity key');
      }
      const spkTs = bundle?.spkTs ?? NaN;
      if (!(spkTs >= directory.now - 60 * MINUTE_MS && spkTs <= directory.now + 10 * MINUTE_MS)) {
        return refusal('signed_prekey_timestamp_out_of_window', 'Signed prekey timestamp is out of the window');
      }
      if (bundle.spkId <= directory.spkId) return refusal('validation_failed', 'spkId must increase with every rotation');
      directory.spkId = bundle.spkId;
      directory.bundles.push(body.signedPrekeyBundle);
      return [200, { spkId: bundle.spkId }];
    }
    return [404, { code: 'not_found', message: `unexpected ${method} ${path}` }];
  };
  return directory;
}

// run(serverNow, { clock }): one maintenance run while the directory's clock
// reads serverNow; the device's corrected clock reads the same unless
// `clock` says otherwise.
async function harness({ available = 0, failRotation = false, failUploads = 0, uploadFailure } = {}) {
  let record = await generateIdentity(subtle, { nowMs: START });
  const identity = {
    current: () => record,
    update: vi.fn(async (fields) => { record = { ...record, ...fields }; }),
  };
  const directory = fakeDirectory(record.ik.publicKey, { available, failRotation, failUploads, uploadFailure });
  const authedApi = vi.fn(async (path, options) => {
    const [status, body] = await directory.handle(path, options);
    if (status >= 400) throw Object.assign(new Error(body.message), { status, code: body.code });
    return body;
  });
  const opkKv = createMemoryKv('keyId');
  const run = (serverNow, { clock = serverNow } = {}) => {
    directory.now = serverNow;
    return maintainPrekeys({
      subtle,
      keys: createKeySource(webcrypto),
      authedApi,
      identity,
      opkKv,
      clock: () => clock,
    });
  };
  return { identity, directory, authedApi, opkKv, run, record: () => record };
}

describe('prekey maintenance', () => {
  it('uploads a batch of non-extractable one-time prekeys when below the threshold, ids never reused', async () => {
    const h = await harness({ available: 0 });
    await h.run(START);
    expect(h.directory.uploads).toHaveLength(ONE_TIME_PREKEY_BATCH);
    const stored = await h.opkKv.all();
    expect(stored).toHaveLength(ONE_TIME_PREKEY_BATCH);
    expect(stored.every((row) => row.privateKey.extractable === false)).toBe(true);
    expect(h.directory.uploads.map((p) => decodeBase64Url(p.publicKey).length)).toEqual(Array(ONE_TIME_PREKEY_BATCH).fill(32));

    // 25 left: enough, nothing uploaded.
    h.directory.available = 25;
    await h.run(START + DAY_MS);
    expect(h.directory.uploads).toHaveLength(ONE_TIME_PREKEY_BATCH);

    // 19 left: another batch, with fresh ids.
    h.directory.available = 19;
    await h.run(START + 2 * DAY_MS);
    const ids = h.directory.uploads.map((p) => p.keyId);
    expect(ids).toHaveLength(2 * ONE_TIME_PREKEY_BATCH);
    expect(new Set(ids).size).toBe(ids.length);
    expect(Math.min(...ids)).toBeGreaterThan(0);
  });

  it('rotates the signed prekey after 7 days and keeps the old one for its grace period', async () => {
    const h = await harness({ available: 100 });
    await h.run(START + SIGNED_PREKEY_ROTATION_MS - 1);
    expect(h.directory.bundles).toEqual([]);

    const rotatedAt = START + SIGNED_PREKEY_ROTATION_MS;
    await h.run(rotatedAt);
    expect(h.directory.bundles).toHaveLength(1);
    const published = await verifyBundle(subtle, h.directory.bundles[0], h.record().ik.publicKey, { nowMs: rotatedAt });
    expect(published).toMatchObject({ spkId: 2, spkTs: rotatedAt });
    expect(h.record().signedPrekeys.map((spk) => [spk.id, spk.supersededAt])).toEqual([[2, null], [1, rotatedAt]]);

    // A handshake from a bundle fetched before the rotation still finds SPK 1
    // during the grace period, and no longer after it.
    const keyring = (nowMs) => createLocalKeyring({
      loadIdentity: async () => h.record(),
      opkKv: createMemoryKv('keyId'),
      clock: () => nowMs,
    });
    const header = { signedPrekeyId: 1, oneTimePrekeyId: NO_ONE_TIME_PREKEY_ID };
    await expect(keyring(rotatedAt + SIGNED_PREKEY_GRACE_MS).claimHandshakePrekeys(header)).resolves.toBeDefined();
    await expect(keyring(rotatedAt + SIGNED_PREKEY_GRACE_MS + 1).claimHandshakePrekeys(header))
      .rejects.toBeInstanceOf(PrekeyUnavailableError);

    // The next maintenance after the grace period drops its private key (and
    // rotates again: SPK 2 is due by then).
    await h.run(rotatedAt + SIGNED_PREKEY_GRACE_MS + 1);
    expect(h.record().signedPrekeys.map((spk) => spk.id)).toEqual([3, 2]);
  });

  it('stores a successor before publishing it, and keeps it for the grace period when publishing failed', async () => {
    const h = await harness({ available: 100, failRotation: true });
    const due = START + SIGNED_PREKEY_ROTATION_MS;
    await expect(h.run(due)).rejects.toThrow('unavailable');
    // Held locally (so a frame sent to it right away would open) but not
    // published, and the old prekey is not yet superseded.
    expect(h.record().signedPrekeys.map((spk) => [spk.id, spk.publishedAt, spk.supersededAt]))
      .toEqual([[2, null, null], [1, START, null]]);

    const callsBefore = h.authedApi.mock.calls.length;
    h.authedApi.mockImplementation(async (path, { body } = {}) => {
      if (path === '/prekeys/count') return { available: 100 };
      h.directory.bundles.push(body.signedPrekeyBundle);
      return {};
    });
    const publishedAt = due + DAY_MS;
    await h.run(publishedAt);
    expect(h.authedApi.mock.calls.length).toBeGreaterThan(callsBefore);
    const published = await verifyBundle(subtle, h.directory.bundles[0], h.record().ik.publicKey, { nowMs: publishedAt });
    // A fresh key and timestamp under the next id. The failed PUT may have
    // reached the directory with only its response lost, so SPK 2 is kept
    // and, like SPK 1, superseded by SPK 3.
    expect(published).toMatchObject({ spkId: 3, spkTs: publishedAt });
    expect(h.record().signedPrekeys.map((spk) => [spk.id, spk.supersededAt]))
      .toEqual([[3, null], [2, publishedAt], [1, publishedAt]]);
    const keyring = createLocalKeyring({
      loadIdentity: async () => h.record(),
      opkKv: createMemoryKv('keyId'),
      clock: () => publishedAt + SIGNED_PREKEY_GRACE_MS,
    });
    await expect(keyring.claimHandshakePrekeys({ signedPrekeyId: 2, oneTimePrekeyId: NO_ONE_TIME_PREKEY_ID }))
      .resolves.toBeDefined();
  });

  it('drops a successor whose publication never succeeded once it is older than the grace period', async () => {
    const h = await harness({ available: 100, failRotation: true });
    const due = START + SIGNED_PREKEY_ROTATION_MS;
    await expect(h.run(due)).rejects.toThrow('unavailable');
    await expect(h.run(due + SIGNED_PREKEY_GRACE_MS)).rejects.toThrow('unavailable');
    expect(h.record().signedPrekeys.map((spk) => spk.id)).toEqual([3, 2, 1]);

    // A directory that stays unreachable does not pile up keys without end;
    // the published SPK 1 stays until a successor is published.
    await expect(h.run(due + SIGNED_PREKEY_GRACE_MS + SIGNED_PREKEY_RESEND_MS)).rejects.toThrow('unavailable');
    expect(h.record().signedPrekeys.map((spk) => spk.id)).toEqual([4, 3, 1]);
  });

  it('tops up one-time prekeys when the rotation fails, then reports the failure', async () => {
    const h = await harness({ available: 0, failRotation: true });
    await expect(h.run(START + SIGNED_PREKEY_ROTATION_MS)).rejects.toThrow('unavailable');
    expect(h.directory.uploads).toHaveLength(ONE_TIME_PREKEY_BATCH);
  });

  it('publishes an unpublished signed prekey again as it is while under 30 minutes old', async () => {
    const h = await harness({ available: 100, failRotation: true });
    const due = START + SIGNED_PREKEY_ROTATION_MS;
    await expect(h.run(due)).rejects.toThrow('unavailable');
    await expect(h.run(due + SIGNED_PREKEY_RESEND_MS - 1)).rejects.toThrow('unavailable');
    h.directory.failRotation = false;
    await h.run(due + SIGNED_PREKEY_RESEND_MS - 1);
    // The same bundle each time: same id, key and timestamp.
    expect(new Set(h.directory.attempts).size).toBe(1);
    expect(await verifyBundle(subtle, h.directory.bundles[0], h.record().ik.publicKey, { nowMs: due }))
      .toMatchObject({ spkId: 2, spkTs: due });
    expect(h.record().signedPrekeys.map((spk) => [spk.id, spk.publishedAt])).toEqual([[2, due + SIGNED_PREKEY_RESEND_MS - 1], [1, START]]);
  });

  it('draws a successor for an unpublished signed prekey 30 minutes old', async () => {
    const h = await harness({ available: 100, failRotation: true });
    const due = START + SIGNED_PREKEY_ROTATION_MS;
    await expect(h.run(due)).rejects.toThrow('unavailable');
    h.directory.failRotation = false;
    const later = due + SIGNED_PREKEY_RESEND_MS;
    await h.run(later);
    expect(await verifyBundle(subtle, h.directory.bundles[0], h.record().ik.publicKey, { nowMs: later }))
      .toMatchObject({ spkId: 3, spkTs: later });
  });

  it('draws a successor on the next attempt after a timestamp the directory refused', async () => {
    const h = await harness({ available: 100 });
    const due = START + SIGNED_PREKEY_ROTATION_MS;
    // Stamped 15 minutes ahead of the directory's clock: refused.
    await expect(h.run(due, { clock: due + 15 * MINUTE_MS }))
      .rejects.toMatchObject({ status: 400, code: 'signed_prekey_timestamp_out_of_window' });
    expect(h.record().signedPrekeys[0]).toMatchObject({ id: 2, publishedAt: null, refusedAt: due + 15 * MINUTE_MS });

    // Under 30 minutes old by any clock, it is still not sent again.
    const retry = due + MINUTE_MS;
    await h.run(retry);
    expect(h.directory.attempts).toHaveLength(2);
    expect(await verifyBundle(subtle, h.directory.bundles[0], h.record().ik.publicKey, { nowMs: retry }))
      .toMatchObject({ spkId: 3, spkTs: retry });
    // Refused but kept, like any failed one, until its grace period ends.
    expect(h.record().signedPrekeys.map((spk) => [spk.id, spk.supersededAt])).toEqual([[3, null], [2, retry], [1, retry]]);
  });

  it('uploads a one-time prekey batch whose upload failed again as it is', async () => {
    const h = await harness({ available: 0, failUploads: 1 });
    await expect(h.run(START)).rejects.toThrow('unavailable');
    expect(h.directory.uploads).toEqual([]);
    const nextId = h.record().nextOneTimePrekeyId;

    // The next run sends the same keys under the same ids before anything
    // else; the pool is then full, so nothing new is drawn.
    await h.run(START + MINUTE_MS);
    expect(h.directory.uploads.map((prekey) => prekey.keyId)).toEqual(Array.from({ length: ONE_TIME_PREKEY_BATCH }, (_, i) => i + 1));
    const held = await h.opkKv.all();
    expect(h.directory.uploads.map((prekey) => prekey.publicKey)).toEqual(
      held.map((row) => Buffer.from(row.publicKey).toString('base64url')),
    );
    expect(h.record()).toMatchObject({ nextOneTimePrekeyId: nextId, oneTimePrekeyUpload: null });
  });

  it('drops a one-time prekey batch the directory refuses, and tops up with a fresh one', async () => {
    const h = await harness({ available: 0, failUploads: 2, uploadFailure: 400 });
    await expect(h.run(START)).rejects.toThrow('unavailable');
    // Refused again as it is: its keys go, and a fresh batch goes up.
    await h.run(START + MINUTE_MS);
    const fresh = Array.from({ length: ONE_TIME_PREKEY_BATCH }, (_, i) => ONE_TIME_PREKEY_BATCH + i + 1);
    expect(h.directory.uploads.map((prekey) => prekey.keyId)).toEqual(fresh);
    expect((await h.opkKv.all()).map((row) => row.keyId)).toEqual(fresh);
    expect(h.record().oneTimePrekeyUpload).toBeNull();
  });

  // The device's clock is off by more than the directory's window allows.
  // The offset comes from the Date header of every API response
  // (src/platform/api-client.js), and every signed prekey is stamped on the
  // corrected clock, so rotation keeps working and the bundle never goes
  // stale for initiators.
  for (const [label, skew] of [['11 minutes ahead', 11 * MINUTE_MS], ['2 hours behind', -120 * MINUTE_MS]]) {
    it(`a device clock ${label} keeps rotating for 61 days`, async () => {
      await keepsRotating(skew);
    });
  }

  async function keepsRotating(skew) {
    let record = await generateIdentity(subtle, { nowMs: START });
    const identity = { current: () => record, update: async (fields) => { record = { ...record, ...fields }; } };
    const directory = fakeDirectory(record.ik.publicKey, { available: 0, failRotation: false, failUploads: 0 });
    const client = createApiClient({
      fetchImpl: async (url, init) => {
        const [status, body] = await directory.handle(url.replace('/v1', ''), {
          method: init.method,
          body: init.body ? JSON.parse(init.body) : undefined,
        });
        return {
          ok: status < 400,
          status,
          headers: new Headers({ date: new Date(directory.now).toUTCString() }),
          text: async () => JSON.stringify(body),
        };
      },
      baseUrl: '/v1',
      tokenStore: { getAccessToken: () => 'access' },
      now: () => directory.now + skew,
    });
    const opkKv = createMemoryKv('keyId');
    for (let day = 0; day <= 61; day += 1) {
      directory.now = START + day * DAY_MS;
      directory.available = 0;
      await maintainPrekeys({
        subtle,
        keys: createKeySource(webcrypto),
        authedApi: client.authedApi,
        identity,
        opkKv,
        clock: client.serverNow,
      });
    }
    expect(directory.uploads).toHaveLength(62 * ONE_TIME_PREKEY_BATCH);
    expect(directory.spkId).toBe(9);
    const served = await verifyBundle(subtle, directory.bundles.at(-1), record.ik.publicKey, { nowMs: directory.now });
    expect(directory.now - served.spkTs).toBeLessThan(SIGNED_PREKEY_ROTATION_MS);
  }
});
