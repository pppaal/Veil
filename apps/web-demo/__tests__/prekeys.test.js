// The prekey lifecycle against the directory: one-time prekeys topped up in
// batches, the signed prekey rotated weekly and kept for its grace period.

import { describe, expect, it, vi } from 'vitest';
import { webcrypto } from 'node:crypto';

import { decodeBase64Url } from '../src/core/base64url.js';
import { verifyBundle } from '../src/crypto/bundle.js';
import { generateIdentity } from '../src/crypto/identity.js';
import { createKeySource } from '../src/crypto/keys.js';
import {
  createLocalKeyring,
  maintainPrekeys,
  ONE_TIME_PREKEY_BATCH,
  PrekeyUnavailableError,
  SIGNED_PREKEY_GRACE_MS,
  SIGNED_PREKEY_ROTATION_MS,
} from '../src/crypto/prekeys.js';
import { NO_ONE_TIME_PREKEY_ID } from '../src/crypto/x3dh.js';
import { createMemoryKv } from '../src/platform/kv.js';

const { subtle } = webcrypto;
const DAY_MS = 24 * 60 * 60 * 1000;
const START = Date.parse('2026-11-11T09:00:00Z');

async function harness({ available = 0, failRotation = false } = {}) {
  let record = await generateIdentity(subtle, { nowMs: START });
  const identity = {
    current: () => record,
    update: vi.fn(async (fields) => { record = { ...record, ...fields }; }),
  };
  const directory = { available, bundles: [], uploads: [] };
  const authedApi = vi.fn(async (path, { method = 'GET', body } = {}) => {
    if (path === '/prekeys/count') return { available: directory.available };
    if (path === '/prekeys' && method === 'POST') {
      directory.uploads.push(...body.prekeys);
      directory.available += body.prekeys.length;
      return {};
    }
    if (path === '/keys/signed-prekey' && method === 'PUT') {
      if (failRotation) throw Object.assign(new Error('unavailable'), { status: 503 });
      directory.bundles.push(body.signedPrekeyBundle);
      return {};
    }
    throw new Error(`unexpected ${method} ${path}`);
  });
  const opkKv = createMemoryKv('keyId');
  const run = (nowMs) => maintainPrekeys({
    subtle,
    keys: createKeySource(webcrypto),
    authedApi,
    identity,
    opkKv,
    clock: () => nowMs,
  });
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
    await expect(h.run(due + SIGNED_PREKEY_GRACE_MS + 1)).rejects.toThrow('unavailable');
    expect(h.record().signedPrekeys.map((spk) => spk.id)).toEqual([4, 3, 1]);
  });
});
