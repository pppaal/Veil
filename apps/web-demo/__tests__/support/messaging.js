// Two-party harness one level above support/devices.js: each endpoint is the
// app's secure-messaging stack (pins, peer bindings, decrypt-once content
// store, session cipher) over in-memory stores, with a directory the test
// controls. endpoint.peers is the conversation list as the relay names each
// conversation's other member; the crypto resolves the peer as the app does
// (src/app/messaging-stack.js): the bound one first.

import { webcrypto } from 'node:crypto';

import { createLocks } from '../../src/crypto/locks.js';
import { createIdentityTrust, createPinStore } from '../../src/crypto/pins.js';
import { createConversationVerifier, createPeerBindings } from '../../src/domain/peer-bindings.js';
import { createSecureMessaging } from '../../src/features/secure-messaging.js';
import { createContentStore } from '../../src/platform/content-store.js';
import { createMemoryKv } from '../../src/platform/kv.js';
import { CONVERSATION, createDevice, NOW, subtle } from './devices.js';

const random = (length) => webcrypto.getRandomValues(new Uint8Array(length));

export const contentStores = () => ({
  records: createMemoryKv('key', { indexField: 'conversationId', expiryField: 'expiresAt' }),
  keys: createMemoryKv('conversationId'),
});

export const openContentStore = (stores) => createContentStore({ subtle, random, ...stores, locks: createLocks(null) });

// directory: Map handle -> async () => { deviceId, identityKey, signedPrekeyBundle, oneTimePrekey }
// endpoint.now is the time its expiries are judged at; tests move it.
export async function createEndpoint({ userId, deviceId, handle, directory }) {
  const endpoint = {
    userId,
    deviceId,
    handle,
    now: NOW,
    peers: new Map(), // conversationId -> { userId, handle } as the relay lists it
    stores: contentStores(),
    pinKv: createMemoryKv('id', { indexField: 'userId' }),
    pendingKv: createMemoryKv('userId'),
    bindingKv: createMemoryKv('conversationId'),
    lookups: 0,
    keyChanges: [],
  };
  endpoint.device = await createDevice({
    userId,
    deviceId,
    verifyIdentity: (identity) => endpoint.verifyIdentity(identity),
  });

  // As a page load does: everything in memory is rebuilt over the stores,
  // and the identity changes awaiting review are read back.
  endpoint.restart = async () => {
    endpoint.device.restart();
    endpoint.trust = createIdentityTrust({
      pins: createPinStore(endpoint.pinKv),
      pendingKv: endpoint.pendingKv,
      onChange: (changed) => endpoint.keyChanges.push(changed),
    });
    await endpoint.trust.load();
    endpoint.bindings = createPeerBindings(endpoint.bindingKv);
    await endpoint.bindings.load();
    endpoint.peerOf = (conversationId) => endpoint.bindings.get(conversationId) ?? endpoint.peers.get(conversationId) ?? null;
    endpoint.verifyIdentity = createConversationVerifier({ bindings: endpoint.bindings, trust: endpoint.trust, peerOf: endpoint.peerOf });
    endpoint.contentStore = openContentStore(endpoint.stores);
    endpoint.secure = createSecureMessaging({
      cipher: endpoint.device.cipher,
      trust: endpoint.trust,
      lookupPeer: async (peer) => {
        endpoint.lookups += 1;
        return directory.get(peer.handle)();
      },
      contentStore: endpoint.contentStore,
      legacyReader: { decrypt: async () => ({ failure: 'no-key' }) },
      getSelf: () => ({ ...endpoint.device.record, deviceId }),
      getPeer: endpoint.peerOf,
      admitIdentity: endpoint.verifyIdentity,
      clock: () => endpoint.now,
    });
    return endpoint;
  };

  return endpoint.restart();
}

// What the directory serves for an endpoint: its device's current keys and a
// fresh one-time prekey per lookup.
export const directoryEntryOf = (endpoint) => async () => {
  const entry = await endpoint.device.directoryEntry();
  return {
    deviceId: entry.remoteDeviceId,
    identityKey: entry.remoteIdentityKey,
    signedPrekeyBundle: entry.signedPrekeyBundle,
    oneTimePrekey: entry.oneTimePrekey,
  };
};

export async function conversation({ conversationId = CONVERSATION } = {}) {
  const directory = new Map();
  const alice = await createEndpoint({ userId: 'u-alice', deviceId: 'd-alice', handle: 'alice', directory });
  const bob = await createEndpoint({ userId: 'u-bob', deviceId: 'd-bob', handle: 'bob', directory });
  directory.set('alice', directoryEntryOf(alice));
  directory.set('bob', directoryEntryOf(bob));
  alice.peers.set(conversationId, { userId: bob.userId, handle: bob.handle });
  bob.peers.set(conversationId, { userId: alice.userId, handle: alice.handle });
  return { alice, bob, directory };
}

// The summary the server returns for an envelope it stored.
let order = 0;
export function serverMessage(envelope, { clientMessageId, id = webcrypto.randomUUID() } = {}) {
  order += 1;
  return {
    id,
    clientMessageId,
    conversationId: envelope.conversationId,
    senderDeviceId: envelope.senderDeviceId,
    conversationOrder: order,
    version: envelope.version,
    ciphertext: envelope.ciphertext,
    nonce: envelope.nonce,
    messageType: envelope.messageType,
    attachment: envelope.attachment ?? null,
    expiresAt: null,
    serverReceivedAt: new Date(Date.UTC(2026, 10, 11, 9, 0, order)).toISOString(),
    deletedAt: null,
    editedAt: null,
    replyToMessageId: null,
  };
}
