// End-to-end messaging for direct conversations, on protocol v2:
//   seal   starts a session from the key directory when there is none (the
//          peer's key checked against its pin first), keeps our own content
//          in the decrypt-once store, then encrypts
//   open   returns a message's content from that store, or decrypts it
//          exactly once and stores the result before the session moves on
//   retire drops what was kept of a message that was deleted or expired
// A peer whose identity changed is frozen here for sending until the user
// reviews the change; nothing in this module ever refetches keys because a
// message failed to decrypt.

import { effectiveExpiry, isPast } from '../core/expiry.js';
import { BundleError } from '../crypto/bundle.js';
import { LEGACY_ENVELOPE_VERSION } from '../crypto/frame.js';
import { isLegacyIdentity } from '../crypto/identity.js';
import { isLegacyV1DevEnvelope } from '../crypto/legacy-v1dev.js';
import { DecryptStatus, RecipientNotAdmittedError } from '../crypto/session-cipher.js';
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
// (src/crypto/identity.js) with its deviceId; clock() -> ms, for expiries.
export function createSecureMessaging({ cipher, trust, lookupPeer, contentStore, legacyReader, getSelf, getPeer, clock }) {
  const bootstrapping = new Map(); // conversationId -> Promise

  const isOwn = (raw) => raw.senderDeviceId === getSelf()?.deviceId && !isLegacyV1DevEnvelope(raw);

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

  // The session may be bound to an identity the pins no longer admit (the
  // user verified another of the peer's devices since): then the cipher
  // seals nothing, and the change it recorded freezes the conversation.
  async function encrypt(conversationId, peer, content) {
    try {
      return await cipher.encrypt({
        conversationId,
        senderDeviceId: getSelf().deviceId,
        recipientUserId: peer.userId,
        payload: payloadFromContent(content),
      });
    } catch (error) {
      if (error instanceof RecipientNotAdmittedError) throw new PeerKeyChangedError(peer.userId);
      throw error;
    }
  }

  // Keeps freshly decrypted content, unless it has already expired: then
  // nothing of it is written, though its message key is spent all the same.
  async function keep(raw, content) {
    const expiresAt = effectiveExpiry(content.expiresAt, raw.expiresAt);
    if (isPast(expiresAt, clock())) {
      await contentStore.retire(raw.conversationId, raw.id);
      return { failure: 'retired' };
    }
    await contentStore.put(raw.conversationId, raw.id, { content, nonce: raw.nonce }, { expiresAt });
    return { content };
  }

  // Decrypts once; the content is in the store before the session commits,
  // so it survives whatever happens next.
  async function decryptOnce(raw) {
    if (isLegacyV1DevEnvelope(raw)) {
      const legacy = await legacyReader.decrypt(raw);
      if (typeof legacy.payload !== 'string') return { failure: legacy.failure };
      return keep(raw, contentFromLegacy(legacy.payload));
    }
    if (!raw.version || raw.version === LEGACY_ENVELOPE_VERSION) return { failure: 'legacy' };
    let kept = null;
    const result = await cipher.decrypt(raw, {
      beforeCommit: async (payload) => {
        kept = await keep(raw, contentFromPayload(payload));
      },
    });
    if (result.status === DecryptStatus.OK) return kept;
    // Another tab may have decrypted it first.
    if (result.status === DecryptStatus.REPLAYED) {
      const stored = await contentStore.get(raw.conversationId, raw.id);
      if (stored?.retired) return { failure: 'retired' };
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

    // Files our own content under the id the server gave the message, with
    // the expiry the relay set on it: the record must expire with it even if
    // the message is never shown again.
    acknowledge: (message) => contentStore.move(
      message.conversationId,
      clientKey(message.clientMessageId),
      message.id,
      { expiresAt: effectiveExpiry(null, message.expiresAt) },
    ),

    // { content } or { failure }: 'retired' for a message deleted or
    // expired, 'cleared' for history this device deleted, or why it is
    // locked. Our own protocol-v2 messages cannot be decrypted (their keys
    // were single-use), so they come only from the store.
    async open(raw) {
      const cleared = await contentStore.get(raw.conversationId, HISTORY_CLEARED);
      if (cleared && raw.conversationOrder <= cleared.throughOrder) return { failure: 'cleared' };
      const own = isOwn(raw);
      let stored = await contentStore.get(raw.conversationId, raw.id);
      if (!stored && own && raw.clientMessageId) {
        await contentStore.move(raw.conversationId, clientKey(raw.clientMessageId), raw.id, {
          expiresAt: effectiveExpiry(null, raw.expiresAt),
        });
        stored = await contentStore.get(raw.conversationId, raw.id);
      }
      if (stored?.retired) return { failure: 'retired' };
      if (own) return stored ? { content: stored.content } : { failure: 'own-missing' };
      if (stored?.nonce === raw.nonce) return { content: stored.content };
      const opened = await decryptOnce(raw);
      // An edit that does not open keeps the last content that did; one that
      // retired the message does not.
      if (opened.content || opened.failure === 'retired' || !stored) return opened;
      return { content: stored.content };
    },

    // For good: a ciphertext of it the relay serves again stays hidden.
    async retire(raw) {
      await contentStore.retire(raw.conversationId, raw.id);
      if (isOwn(raw) && raw.clientMessageId) await contentStore.delete(raw.conversationId, clientKey(raw.clientMessageId));
    },

    // The peer key a safety number in this conversation is about
    // (src/crypto/pins.js safetyKey): the identity its session sends to,
    // unless a change waits for review. Null outside a direct conversation.
    async safetyKey(conversationId) {
      const peer = getPeer(conversationId);
      return peer ? trust.safetyKey(peer.userId, await cipher.sessionIdentity(conversationId)) : null;
    },

    // Retires every stored message whose expiry has passed, shown or not.
    retireExpired: () => contentStore.retireExpired(clock()),

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
