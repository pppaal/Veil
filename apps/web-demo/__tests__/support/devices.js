// In-memory protocol-v2 devices for the crypto tests: an identity record, the
// stores a browser keeps in IndexedDB (here createMemoryKv, which copies like
// structured clone does) and a session cipher on top. restart() builds a new
// cipher, keyring and lock set over the same stores, as a page reload does.

import { webcrypto } from 'node:crypto';

import { generateIdentity, publishedKeys } from '../../src/crypto/identity.js';
import { createKeySource } from '../../src/crypto/keys.js';
import { createLocks } from '../../src/crypto/locks.js';
import { createLocalKeyring } from '../../src/crypto/prekeys.js';
import { createSessionCipher } from '../../src/crypto/session-cipher.js';
import { createSessionRepo } from '../../src/crypto/session-repo.js';
import { decodeBase64Url } from '../../src/core/base64url.js';
import { createMemoryKv } from '../../src/platform/kv.js';

export const { subtle } = webcrypto;
export const NOW = Date.parse('2026-11-11T09:00:00Z');
export const CONVERSATION = '6f0c1a2b-3d4e-4f50-8a9b-0c1d2e3f4a5b';

export async function createDevice({
  userId,
  deviceId,
  identity = null,
  keys = createKeySource(webcrypto),
  clock = () => NOW,
  verifyIdentity = null,
  stores = { sessions: createMemoryKv('conversationId'), oneTimePrekeys: createMemoryKv('keyId') },
} = {}) {
  const record = identity ?? await generateIdentity(subtle, { nowMs: clock() });
  const device = { userId, deviceId, record, stores, keys, clock };

  device.restart = () => {
    device.keyring = createLocalKeyring({ loadIdentity: async () => device.record, opkKv: stores.oneTimePrekeys, clock });
    device.repo = createSessionRepo({
      subtle,
      random: (length) => webcrypto.getRandomValues(new Uint8Array(length)),
      getKek: async () => device.record.sessionKek,
      kv: stores.sessions,
      clock,
    });
    device.cipher = createSessionCipher({
      subtle,
      keys: device.keys,
      repo: device.repo,
      locks: createLocks(null),
      keyring: device.keyring,
      clock,
      verifyIdentity,
    });
    return device;
  };

  let nextOneTimePrekeyId = 1;
  device.addOneTimePrekey = async () => {
    const pair = await keys.x25519();
    const keyId = nextOneTimePrekeyId;
    nextOneTimePrekeyId += 1;
    await stores.oneTimePrekeys.put({ keyId, privateKey: pair.privateKey, publicKey: pair.publicKey });
    return { keyId, publicKey: pair.publicKey };
  };

  // What GET /v1/keys/:handle serves for this device.
  device.directoryEntry = async ({ oneTimePrekey = true } = {}) => {
    const published = await publishedKeys(subtle, device.record);
    return {
      remoteDeviceId: deviceId,
      remoteIdentityKey: decodeBase64Url(published.publicIdentityKey),
      signedPrekeyBundle: published.signedPrekeyBundle,
      oneTimePrekey: oneTimePrekey ? await device.addOneTimePrekey() : null,
    };
  };

  return device.restart();
}

export async function connect(initiator, responder, { conversationId = CONVERSATION, oneTimePrekey = true } = {}) {
  const entry = await responder.directoryEntry({ oneTimePrekey });
  await initiator.cipher.bootstrap({ conversationId, ...entry });
  return entry;
}

export function send(from, to, body, { conversationId = CONVERSATION, kind = 'text', attachment = null } = {}) {
  return from.cipher.encrypt({
    conversationId,
    senderDeviceId: from.deviceId,
    recipientUserId: to.userId,
    payload: { body, kind, expiresAt: null, attachment },
  });
}

export const receive = (device, envelope) => device.cipher.decrypt(envelope);

export async function pair() {
  const alice = await createDevice({ userId: 'u-alice', deviceId: 'd-alice' });
  const bob = await createDevice({ userId: 'u-bob', deviceId: 'd-bob' });
  return { alice, bob };
}
