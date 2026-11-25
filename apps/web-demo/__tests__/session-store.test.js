// The session record as several tabs share it: each tab's session store
// holds its own copy, and no tab's write may revert fields another tab saved.

import { describe, expect, it, vi } from 'vitest';
import { webcrypto } from 'node:crypto';

import { generateIdentity } from '../src/crypto/identity.js';
import { createKeySource } from '../src/crypto/keys.js';
import {
  createLocalKeyring,
  maintainPrekeys,
  ONE_TIME_PREKEY_BATCH,
  SIGNED_PREKEY_ROTATION_MS,
} from '../src/crypto/prekeys.js';
import { createMemoryKv } from '../src/platform/kv.js';
import { createSessionStore } from '../src/platform/session-store.js';
import { memorySessionRepo } from './support/session-repo.js';

const { subtle } = webcrypto;
const START = Date.parse('2026-11-11T09:00:00Z');

async function sessionRecord(handle) {
  return {
    handle,
    userId: `user-${handle}`,
    deviceId: `device-${handle}`,
    ...(await generateIdentity(subtle, { nowMs: START })),
    accessToken: 'access-0',
    refreshToken: 'refresh-0',
  };
}

// Two tabs of one browser: a session store each over the one stored record.
async function twoTabs() {
  const repo = memorySessionRepo(await sessionRecord('alice'), { clone: true });
  const tabA = createSessionStore({ repo, subtle });
  const tabB = createSessionStore({ repo, subtle });
  await tabA.load();
  await tabB.load();
  return { repo, tabA, tabB };
}

function fakeDirectory() {
  const directory = { available: 0, uploads: [], bundles: [] };
  directory.authedApi = vi.fn(async (path, { method = 'GET', body } = {}) => {
    if (path === '/prekeys/count') return { available: directory.available };
    if (path === '/prekeys' && method === 'POST') {
      directory.uploads.push(...body.prekeys.map((prekey) => prekey.keyId));
      directory.available += body.prekeys.length;
      return {};
    }
    if (path === '/keys/signed-prekey' && method === 'PUT') {
      directory.bundles.push(body.signedPrekeyBundle);
      return {};
    }
    throw new Error(`unexpected ${method} ${path}`);
  });
  return directory;
}

describe('session store shared by tabs', () => {
  it('a token save in one tab keeps the prekey state another tab saved', async () => {
    const { repo, tabA, tabB } = await twoTabs();
    const directory = fakeDirectory();
    const opkKv = createMemoryKv('keyId');
    // As app.js runs maintenance: under PREKEY_LOCK, on the record as stored.
    const maintain = async (tab, nowMs) => {
      await tab.reload();
      await maintainPrekeys({
        subtle,
        keys: createKeySource(webcrypto),
        authedApi: directory.authedApi,
        identity: { current: () => tab.current(), update: (fields) => tab.update(fields) },
        opkKv,
        clock: () => nowMs,
      });
    };

    const rotatedAt = START + SIGNED_PREKEY_ROTATION_MS;
    await maintain(tabA, rotatedAt);
    expect(directory.bundles).toHaveLength(1);
    expect(directory.uploads).toHaveLength(ONE_TIME_PREKEY_BATCH);

    // Tab B still holds the record from before that run when it renews and
    // then drops its tokens.
    await tabB.saveTokens({ accessToken: 'access-1', refreshToken: 'refresh-1' });
    await tabB.clearTokens();
    expect(repo.peek()).toMatchObject({
      nextOneTimePrekeyId: ONE_TIME_PREKEY_BATCH + 1,
      accessToken: null,
      refreshToken: null,
    });
    expect(repo.peek().signedPrekeys.map((spk) => spk.id)).toEqual([2, 1]);

    // Tab B answers a handshake to the rotated prekey and a one-time prekey
    // of the batch tab A uploaded.
    const keyring = createLocalKeyring({ loadIdentity: () => tabB.reload(), opkKv, clock: () => rotatedAt });
    await expect(keyring.claimHandshakePrekeys({ signedPrekeyId: 2, oneTimePrekeyId: 1 })).resolves.toBeDefined();

    // The next batch, from either tab, takes fresh ids.
    directory.available = 0;
    await maintain(tabB, rotatedAt + 1);
    expect(directory.uploads).toHaveLength(2 * ONE_TIME_PREKEY_BATCH);
    expect(new Set(directory.uploads).size).toBe(directory.uploads.length);
    expect(directory.bundles).toHaveLength(1);
  });

  it('a tab writes only to the identity it holds', async () => {
    const { repo, tabA, tabB } = await twoTabs();
    const held = tabA.current().edPubB64u;

    // A device transfer completing in tab B replaces the stored identity.
    const transferred = { ...(await sessionRecord('bob')), accessToken: null, refreshToken: null };
    await tabB.save(transferred);
    await tabA.saveTokens({ accessToken: 'access-a', refreshToken: 'refresh-a', userId: 'user-alice' });
    await tabA.update({ nextOneTimePrekeyId: 500 });
    await tabA.reload();

    expect(repo.peek()).toMatchObject({ handle: 'bob', edPubB64u: transferred.edPubB64u, accessToken: null });
    expect(repo.peek().nextOneTimePrekeyId).toBe(1);
    // Tab A goes on with its own identity until it reloads.
    expect(tabA.current()).toMatchObject({ handle: 'alice', edPubB64u: held, accessToken: 'access-a' });

    // Nor does a write recreate a record another tab deleted.
    await repo.put(null);
    await tabA.clearTokens();
    expect(repo.peek()).toBeNull();
  });
});
