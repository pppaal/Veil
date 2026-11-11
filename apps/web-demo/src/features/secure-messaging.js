// End-to-end messaging for direct conversations, on protocol v2:
//   seal   starts a session from the key directory when there is none (the
//          peer's key checked against its pin first), keeps our own content
//          in the decrypt-once store, then encrypts
//   open   returns a message's content from that store, or decrypts it
//          exactly once and stores the result before the session moves on
// A peer whose identity changed is frozen here for sending until the user
// reviews the change; nothing in this module ever refetches keys because a
// message failed to decrypt.

import { BundleError } from '../crypto/bundle.js';
import { LEGACY_ENVELOPE_VERSION } from '../crypto/frame.js';
import { isLegacyIdentity } from '../crypto/identity.js';
import { isLegacyV1DevEnvelope } from '../crypto/legacy-v1dev.js';
import { DecryptStatus } from '../crypto/session-cipher.js';
import { contentFromLegacy, contentFromPayload, payloadFromContent } from '../domain/content.js';

export class PeerKeyChangedError extends Error {
  constructor(userId) {
    super('peer identity key changed; review it before sending');
    this.name = 'PeerKeyChangedError';
    this.userId = userId;
  }
}

// This device's identity predates protocol v2 (src/crypto/identity.js) and
// can never send again.
export class LegacyIdentityError extends Error {
  constructor() {
    super('this identity predates protocol v2 and cannot send');
    this.name = 'LegacyIdentityError';
  }
}

export class PeerUnavailableError extends Error {
  // reason: 'no-peer' (no other member, or we do not know who we are yet),
  // 'not-upgraded' (the peer's client predates protocol v2) or 'bad-bundle'.
  constructor(reason) {
    super(`cannot start a session: ${reason}`);
    this.name = 'PeerUnavailableError';
    this.reason = reason;
  }
}

// Our own sends are stored under their client id until the server names them.
const clientKey = (clientMessageId) => `client:${clientMessageId}`;
// The content-store record marking how much of a conversation's history this
// device deleted; message ids are UUIDs, so it cannot collide with one.
const HISTORY_CLEARED = 'history-cleared';

// lookupPeer(peer) -> { deviceId, identityKey, signedPrekeyBundle, oneTimePrekey }
// from GET /v1/keys/:handle?claim=active, or a BundleError when the claimed
// one-time prekey is malformed; getPeer(conversationId) -> the other member
// { userId, handle } or null; getSelf() -> the signed-in identity record
// (src/crypto/identity.js) with its deviceId.
export function createSecureMessaging({ cipher, trust, lookupPeer, contentStore, legacyReader, getSelf, getPeer }) {
  const bootstrapping = new Map(); // conversationId -> Promise

  async function bootstrap(conversationId, peer) {
    let started;
    try {
      const entry = await lookupPeer(peer);
      started = await cipher.bootstrap({
        conversationId,
        remoteDeviceId: entry.deviceId,
        remoteIdentityKey: entry.identityKey,
        signedPrekeyBundle: entry.signedPrekeyBundle,
        oneTimePrekey: entry.oneTimePrekey,
        admit: () => trust.admit(peer.userId, entry.deviceId, entry.identityKey),
      });
    } catch (error) {
      if (error instanceof BundleError) {
        throw new PeerUnavailableError(error.reason === 'unsupported' ? 'not-upgraded' : 'bad-bundle');
      }
      throw error;
    }
    if (!started) throw new PeerKeyChangedError(peer.userId);
  }

  // Resolves to the peer once a session exists. Concurrent sends share one
  // bootstrap, so they do not each claim a one-time prekey.
  async function prepare(conversationId) {
    if (isLegacyIdentity(getSelf())) throw new LegacyIdentityError();
    const peer = getPeer(conversationId);
    if (!peer) throw new PeerUnavailableError('no-peer');
    if (trust.pendingChange(peer.userId)) throw new PeerKeyChangedError(peer.userId);
    if (await cipher.hasSession(conversationId)) return peer;
    if (!bootstrapping.has(conversationId)) {
      const run = bootstrap(conversationId, peer).finally(() => bootstrapping.delete(conversationId));
      bootstrapping.set(conversationId, run);
    }
    await bootstrapping.get(conversationId);
    return peer;
  }

  async function encrypt(conversationId, peer, content) {
    return cipher.encrypt({
      conversationId,
      senderDeviceId: getSelf().deviceId,
      recipientUserId: peer.userId,
      payload: payloadFromContent(content),
    });
  }

  // Decrypts once; the content is in the store before the session commits,
  // so it survives whatever happens next.
  async function decryptOnce(raw) {
    const store = (content) => contentStore.put(raw.conversationId, raw.id, { content, nonce: raw.nonce });
    if (isLegacyV1DevEnvelope(raw)) {
      const legacy = await legacyReader.decrypt(raw);
      if (typeof legacy.payload !== 'string') return { failure: legacy.failure };
      const content = contentFromLegacy(legacy.payload);
      await store(content);
      return { content };
    }
    if (!raw.version || raw.version === LEGACY_ENVELOPE_VERSION) return { failure: 'legacy' };
    let content = null;
    const result = await cipher.decrypt(raw, {
      beforeCommit: async (payload) => {
        content = contentFromPayload(payload);
        await store(content);
      },
    });
    if (result.status === DecryptStatus.OK) return { content };
    // Another tab may have decrypted it first.
    if (result.status === DecryptStatus.REPLAYED) {
      const stored = await contentStore.get(raw.conversationId, raw.id);
      if (stored) return { content: stored.content };
    }
    return { failure: result.status };
  }

  return {
    prepare,

    // Resolves to the envelope for POST /messages. Our content is stored
    // before anything is encrypted, so a sent message never becomes
    // unreadable to us.
    async seal(conversationId, content, { clientMessageId }) {
      const peer = await prepare(conversationId);
      await contentStore.put(conversationId, clientKey(clientMessageId), { content, nonce: null });
      try {
        return await encrypt(conversationId, peer, content);
      } catch (error) {
        await contentStore.delete(conversationId, clientKey(clientMessageId));
        throw error;
      }
    },

    // An edit is a new frame; its content replaces the message's once the
    // server has accepted it (rememberEdit).
    async sealEdit(conversationId, content) {
      return encrypt(conversationId, await prepare(conversationId), content);
    },

    rememberEdit: (conversationId, messageId, content, nonce) =>
      contentStore.put(conversationId, messageId, { content, nonce }),

    // Files our own content under the id the server gave the message.
    acknowledge: (message) => contentStore.move(message.conversationId, clientKey(message.clientMessageId), message.id),

    // { content } or { failure }. Our own protocol-v2 messages cannot be
    // decrypted (their keys were single-use), so they come only from the
    // store.
    async open(raw) {
      const cleared = await contentStore.get(raw.conversationId, HISTORY_CLEARED);
      if (cleared && raw.conversationOrder <= cleared.throughOrder) return { failure: 'cleared' };
      const own = raw.senderDeviceId === getSelf()?.deviceId && !isLegacyV1DevEnvelope(raw);
      let stored = await contentStore.get(raw.conversationId, raw.id);
      if (!stored && own && raw.clientMessageId) {
        await contentStore.move(raw.conversationId, clientKey(raw.clientMessageId), raw.id);
        stored = await contentStore.get(raw.conversationId, raw.id);
      }
      if (own) return stored ? { content: stored.content } : { failure: 'own-missing' };
      if (stored?.nonce === raw.nonce) return { content: stored.content };
      const opened = await decryptOnce(raw);
      // An edit that does not open keeps the last content that did.
      return opened.content || !stored ? opened : { content: stored.content };
    },

    forgetMessage: (conversationId, messageId) => contentStore.delete(conversationId, messageId),

    // Deletes this device's history of a conversation up to throughOrder by
    // crypto-shredding its content key. The relay may still hold those
    // ciphertexts, but their message keys are spent: they stay hidden
    // rather than shown as failures.
    async forgetConversation(conversationId, throughOrder) {
      await contentStore.deleteConversation(conversationId);
      await contentStore.put(conversationId, HISTORY_CLEARED, { throughOrder });
    },
  };
}
