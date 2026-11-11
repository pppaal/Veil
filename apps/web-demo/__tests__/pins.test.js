import { describe, expect, it, vi } from 'vitest';
import { webcrypto } from 'node:crypto';

import { generateIdentity } from '../src/crypto/identity.js';
import { createDevEnvelopeCrypto, PeerKeyChangedError } from '../src/crypto/dev-envelope.js';
import { createPeerKeyDirectory, createPinStore } from '../src/crypto/pins.js';

const CONVERSATION = 'c-1';

function pinRepo() {
  const rows = new Map();
  return {
    rows,
    get: vi.fn(async (userId) => rows.get(userId) ?? null),
    put: vi.fn(async (pin) => { rows.set(pin.userId, pin); }),
  };
}

async function device(userId, deviceId) {
  return { userId, deviceId, ...(await generateIdentity(webcrypto.subtle)) };
}

// One side of a direct conversation: its own identity, a directory that
// serves `peerKey()` for the other user, and the envelope crypto on top.
function endpoint({ self, peer, peerKey, repo, onKeyChange }) {
  const fetchPeerKey = vi.fn(async () => peerKey());
  const directory = createPeerKeyDirectory({ fetchPeerKey, pins: createPinStore(repo), onKeyChange });
  const crypto = createDevEnvelopeCrypto({
    crypto: webcrypto,
    directory,
    getSelf: () => self,
    getPeer: (conversationId) => (conversationId === CONVERSATION ? { userId: peer.userId, handle: 'peer' } : null),
  });
  return { fetchPeerKey, directory, crypto };
}

describe('identity pins', () => {
  it('pins the first key and reports later matches', async () => {
    let clock = 0;
    const repo = pinRepo();
    const pins = createPinStore(repo, { now: () => `t${++clock}` });
    expect(await pins.check('u-bob', 'key-1')).toEqual({ status: 'pinned', pin: { userId: 'u-bob', peerKey: 'key-1', firstSeenAt: 't1' } });
    expect((await pins.check('u-bob', 'key-1')).status).toBe('match');
    expect((await pins.check('u-bob', 'key-2')).status).toBe('changed');
    expect(repo.rows.get('u-bob').peerKey).toBe('key-1');
  });

  it('changed peer key freezes sending until accepted', async () => {
    const alice = await device('u-alice', 'd-alice');
    const bobOld = await device('u-bob', 'd-bob-old');
    const bobNew = await device('u-bob', 'd-bob-new');
    const repo = pinRepo();

    // First session pins Bob's original key.
    const firstSession = endpoint({ self: alice, peer: bobOld, peerKey: () => bobOld.xPubB64u, repo });
    expect(await firstSession.crypto.ensureSendable(CONVERSATION)).toBe(true);
    expect(repo.rows.get('u-bob').peerKey).toBe(bobOld.xPubB64u);

    // After a reload the directory serves a different key for Bob.
    const onKeyChange = vi.fn();
    const alicePage = endpoint({ self: alice, peer: bobNew, peerKey: () => bobNew.xPubB64u, repo, onKeyChange });
    await expect(alicePage.crypto.encrypt(CONVERSATION, 'hello')).rejects.toBeInstanceOf(PeerKeyChangedError);
    await expect(alicePage.crypto.ensureSendable(CONVERSATION)).rejects.toBeInstanceOf(PeerKeyChangedError);
    expect(onKeyChange).toHaveBeenCalledWith('u-bob');
    expect(alicePage.directory.pendingChange('u-bob')).toBe(bobNew.xPubB64u);
    expect(repo.rows.get('u-bob').peerKey).toBe(bobOld.xPubB64u);

    // Explicit acceptance re-pins and unfreezes; the new key is the one used.
    expect(await alicePage.directory.accept('u-bob')).toBe(true);
    alicePage.crypto.forgetPeer('u-bob');
    expect(alicePage.directory.pendingChange('u-bob')).toBeNull();
    expect(repo.rows.get('u-bob').peerKey).toBe(bobNew.xPubB64u);
    const sealed = await alicePage.crypto.encrypt(CONVERSATION, 'hello');

    const bobPage = endpoint({ self: bobNew, peer: alice, peerKey: () => alice.xPubB64u, repo: pinRepo() });
    expect(await bobPage.crypto.decrypt({ conversationId: CONVERSATION, senderDeviceId: 'd-alice', ...sealed }))
      .toEqual({ payload: 'hello' });
  });

  it('no refetch after decrypt failures', async () => {
    const alice = await device('u-alice', 'd-alice');
    const bob = await device('u-bob', 'd-bob');
    const repo = pinRepo();
    const alicePage = endpoint({ self: alice, peer: bob, peerKey: () => bob.xPubB64u, repo });
    const bobPage = endpoint({ self: bob, peer: alice, peerKey: () => alice.xPubB64u, repo: pinRepo() });
    const genuine = await bobPage.crypto.encrypt(CONVERSATION, 'genuine');

    const tampered = genuine.ciphertext.slice(0, -2) + (genuine.ciphertext.endsWith('AA') ? 'BB' : 'AA');
    const attempts = [
      { ciphertext: tampered, nonce: genuine.nonce },
      { ciphertext: 'v2.AAAA', nonce: genuine.nonce },
      { ciphertext: 'v2.!!!', nonce: genuine.nonce },
      { ciphertext: genuine.ciphertext, nonce: 'AAAAAAAAAAAAAAAA' },
      { ciphertext: tampered, nonce: genuine.nonce },
    ];
    for (const attempt of attempts) {
      expect(await alicePage.crypto.decrypt({ conversationId: CONVERSATION, senderDeviceId: 'd-bob', ...attempt }))
        .toEqual({ failure: 'failed' });
    }
    expect(alicePage.fetchPeerKey).toHaveBeenCalledTimes(1);
    expect(repo.put).toHaveBeenCalledTimes(1);
    expect(await alicePage.crypto.decrypt({ conversationId: CONVERSATION, senderDeviceId: 'd-bob', ...genuine }))
      .toEqual({ payload: 'genuine' });
    expect(alicePage.fetchPeerKey).toHaveBeenCalledTimes(1);
  });

  it('retries an unreachable directory but not a resolved key', async () => {
    const pins = createPinStore(pinRepo());
    const fetchPeerKey = vi.fn()
      .mockRejectedValueOnce(new Error('offline'))
      .mockResolvedValue('key-1');
    const directory = createPeerKeyDirectory({ fetchPeerKey, pins });
    await expect(directory.resolve('u-bob', 'bob')).rejects.toThrow('offline');
    await expect(directory.resolve('u-bob', 'bob')).resolves.toEqual({ trustedKey: 'key-1', pendingKey: null });
    await directory.resolve('u-bob', 'bob');
    expect(fetchPeerKey).toHaveBeenCalledTimes(2);
    expect(await directory.accept('u-bob')).toBe(false);
  });
});
