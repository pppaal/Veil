// Builds what the app runs on beneath the UI: IndexedDB, the device's
// session record, the REST client, and the protocol-v2 stack (src/crypto/):
// pins and identity trust, the session cipher, the decrypt-once content
// store, secure messaging and the sender. Every crypto store is IndexedDB,
// written only while an identity is stored, and every private key in them
// is a non-extractable CryptoKey.

import { decodeBase64Url } from '../core/base64url.js';
import { isLegacyIdentity } from '../crypto/identity.js';
import { createKeySource } from '../crypto/keys.js';
import { createLegacyV1DevReader } from '../crypto/legacy-v1dev.js';
import { createLocks } from '../crypto/locks.js';
import { createIdentityTrust, createPinStore } from '../crypto/pins.js';
import { claimedOneTimePrekey, createLocalKeyring, maintainPrekeys, PREKEY_LOCK } from '../crypto/prekeys.js';
import { createSessionCipher } from '../crypto/session-cipher.js';
import { createSessionRepo } from '../crypto/session-repo.js';
import { directPeer } from '../domain/conversations.js';
import { createHistoryMarks } from '../domain/history.js';
import { createAttachmentFetcher } from '../domain/media.js';
import { createSecureMessaging } from '../features/secure-messaging.js';
import { createSender } from '../features/sender.js';
import { createApiClient } from '../platform/api-client.js';
import { createContentStore } from '../platform/content-store.js';
import { createIdb } from '../platform/idb.js';
import { createIdbKv } from '../platform/kv.js';
import { createIdbSessionRepo, createSessionStore } from '../platform/session-store.js';
import { webStorage } from './services/preferences.js';

const API = '/v1';
// Pre-IndexedDB builds kept the session record in localStorage.
const LEGACY_SESSION_KEY = 'veil-demo-session';
const PREKEY_MAINTENANCE_MS = 6 * 60 * 60 * 1000;

async function migrateLegacySession(idb) {
  const storage = webStorage('localStorage');
  let legacy = null;
  try {
    legacy = JSON.parse(storage?.getItem(LEGACY_SESSION_KEY) ?? 'null');
  } catch {
    return null;
  }
  if (!legacy) return null;
  await idb.put('session', { id: 'me', value: legacy });
  storage.removeItem(LEGACY_SESSION_KEY);
  return legacy;
}

// hooks: onStorageBlocked(), onDeletedElsewhere(), onSessionRejected(),
// onTokensSaved(), onTrustChange().
export function createMessagingStack({ store, hooks }) {
  const idb = createIdb(indexedDB, {
    onBlocked: () => hooks.onStorageBlocked(),
    onDeletedElsewhere: () => hooks.onDeletedElsewhere(),
  });
  const sessionStore = createSessionStore({
    repo: createIdbSessionRepo(idb, { readLegacy: () => migrateLegacySession(idb) }),
    subtle: crypto.subtle,
  });

  // Background writes on behalf of the stored identity: caches, the outbound
  // queue, pins. Work still in flight when the identity is destroyed (a
  // refresh landing after the wipe, a send failing into the queue) must not
  // recreate the deleted database with that identity's data.
  const identityDb = {
    async put(storeName, value) {
      if (sessionStore.current()) await idb.put(storeName, value);
    },
    async delete(storeName, key) {
      if (sessionStore.current()) await idb.delete(storeName, key);
    },
  };

  const apiClient = createApiClient({
    fetchImpl: (url, init) => fetch(url, init),
    baseUrl: API,
    tokenStore: {
      ...sessionStore,
      async saveTokens(tokens) {
        await sessionStore.saveTokens(tokens);
        hooks.onTokensSaved();
      },
    },
    onSessionRejected: () => hooks.onSessionRejected(),
  });
  const { authedApi } = apiClient;

  const locks = createLocks(navigator.locks);
  const keySource = createKeySource(crypto);
  const kv = (storeName, options) => createIdbKv({ ...idb, put: identityDb.put, delete: identityDb.delete }, storeName, options);
  const oneTimePrekeyKv = kv('one-time-prekeys');
  const peerOf = (conversationId) => directPeer(store.conversation(conversationId), store.state.me?.userId);

  const trust = createIdentityTrust({
    pins: createPinStore(kv('identity-pins-v2', { index: 'byUser' }), { locks }),
    pendingKv: kv('identity-pending'),
    onChange: () => hooks.onTrustChange(),
  });

  const cipher = createSessionCipher({
    subtle: crypto.subtle,
    keys: keySource,
    repo: createSessionRepo({
      subtle: crypto.subtle,
      random: keySource.randomBytes,
      getKek: async () => sessionStore.current().sessionKek,
      kv: kv('crypto-sessions'),
      clock: Date.now,
    }),
    locks,
    // Signed prekeys are stamped and aged on the server's clock (contract
    // C-SPK); the clock of everything else stays local.
    keyring: createLocalKeyring({ loadIdentity: () => sessionStore.reload(), opkKv: oneTimePrekeyKv, clock: apiClient.serverNow }),
    clock: Date.now,
    // A session is installed by an authenticated handshake, and a frame is
    // sealed or opened, only for an identity the pins admit for that peer
    // and device.
    verifyIdentity: ({ conversationId, remoteDeviceId, identityKey }) => {
      const peer = peerOf(conversationId);
      return peer ? trust.admit(peer.userId, remoteDeviceId, identityKey) : false;
    },
  });

  const contentStore = createContentStore({
    subtle: crypto.subtle,
    random: keySource.randomBytes,
    records: kv('message-contents', { index: 'byConversation', expiryIndex: 'byExpiry' }),
    keys: kv('content-keys'),
    locks,
  });

  // The peer's active device from the authenticated directory, with a
  // one-time prekey claimed for the handshake.
  async function lookupPeer(peer) {
    const { user, devices } = await authedApi(`/keys/${encodeURIComponent(peer.handle)}?claim=active`);
    if (user?.id !== peer.userId) throw new Error('key directory answered for another user');
    const device = devices?.find((candidate) => candidate.deviceId === user.activeDeviceId);
    if (!device) throw new Error('peer has no active device');
    return {
      deviceId: device.deviceId,
      identityKey: decodeBase64Url(device.identityPublicKey),
      signedPrekeyBundle: device.signedPrekeyBundle,
      oneTimePrekey: claimedOneTimePrekey(device.oneTimePrekey),
    };
  }

  const getSelf = () => store.state.me;
  const secure = createSecureMessaging({
    cipher,
    trust,
    lookupPeer,
    contentStore,
    // History an identity from before protocol v2 wrote, read with the peer
    // key that era pinned.
    legacyReader: createLegacyV1DevReader({
      subtle: crypto.subtle,
      getSelf,
      peerKey: async (conversationId) => {
        const peer = peerOf(conversationId);
        return peer ? (await idb.get('identity-pins', peer.userId))?.peerKey ?? null : null;
      },
    }),
    getSelf,
    getPeer: peerOf,
    clock: Date.now,
  });

  // Keeps the directory able to start sessions with us (src/crypto/prekeys.js),
  // one tab at a time, on the identity as stored now.
  let prekeyTimer = null;
  const prekeys = {
    start() {
      const run = () => locks.run(PREKEY_LOCK, async () => {
        if (isLegacyIdentity(await sessionStore.reload())) return;
        await maintainPrekeys({
          subtle: crypto.subtle,
          keys: keySource,
          authedApi,
          identity: { current: () => sessionStore.current(), update: (fields) => sessionStore.update(fields) },
          opkKv: oneTimePrekeyKv,
          clock: apiClient.serverNow,
        });
      }).catch((error) => console.warn('prekey maintenance failed', error));
      run();
      prekeyTimer = setInterval(run, PREKEY_MAINTENANCE_MS);
    },
    stop() {
      clearInterval(prekeyTimer);
      prekeyTimer = null;
    },
  };

  return {
    idb,
    identityDb,
    sessionStore,
    apiClient,
    api: apiClient.api,
    authedApi,
    keySource,
    trust,
    // How far back each conversation's history has been fetched
    // (src/domain/history.js).
    historyMarks: createHistoryMarks(kv('history-marks')),
    secure,
    sender: createSender({ secure, authedApi, queue: { put: (entry) => identityDb.put('outbound', entry) } }),
    peerOf,
    media: { subtle: crypto.subtle, fetchAttachment: createAttachmentFetcher({ authedApi, fetchImpl: (url) => fetch(url) }) },
    prekeys,
  };
}
