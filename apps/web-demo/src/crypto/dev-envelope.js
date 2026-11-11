// Wire crypto of the web demo's 'veil-envelope-v1-dev' envelopes, byte for
// byte what earlier builds wrote, so existing history keeps decrypting:
//   ciphertext = "v2." + base64url(AES-256-GCM(key, iv = nonce, aad))
//   nonce      = base64url(12 random bytes), also the HKDF salt
//   key        = HKDF-SHA256(ikm = X25519(myX, peerX), salt = nonce,
//                  info = "veil-demo-v2|aesgcm|" + sorted(myXPub, peerXPub) + "|" + conversationId)
//   aad        = buildAad({ conversationId, senderDeviceId }); messages from
//                before the AAD binding decrypt without it.
// One static secret per peer pair: no forward secrecy, no replay protection.
// Wave 2 replaces this with the mobile protocol; do not extend it.
//
// The peer key always comes from the pinned directory entry. A pending key
// change freezes encryption for that peer until the user accepts it.

import { buildAad } from '../../lib/aad.js';
import { decodeBase64Url, encodeBase64Url } from '../core/base64url.js';

export const DEV_ENVELOPE_VERSION = 'veil-envelope-v1-dev';
const CIPHERTEXT_PREFIX = 'v2.';
const NONCE_BYTES = 12;

export class PeerKeyChangedError extends Error {
  constructor(userId) {
    super('peer identity key changed; accept the new key before sending');
    this.name = 'PeerKeyChangedError';
    this.userId = userId;
  }
}

export function createDevEnvelopeCrypto({ crypto, directory, getSelf, getPeer }) {
  const { subtle } = crypto;
  const contexts = new Map(); // conversationId -> { peerUserId, hkdfBase, info }

  async function buildContext(conversationId) {
    const self = getSelf();
    const peer = getPeer(conversationId);
    if (!self?.xPrivKey || !peer) return null;
    const { trustedKey } = await directory.resolve(peer.userId, peer.handle);
    const peerPublic = await subtle.importKey('raw', decodeBase64Url(trustedKey), { name: 'X25519' }, false, []);
    const shared = await subtle.deriveBits({ name: 'X25519', public: peerPublic }, self.xPrivKey, 256);
    const hkdfBase = await subtle.importKey('raw', shared, 'HKDF', false, ['deriveKey']);
    const sortedPublicKeys = [self.xPubB64u, trustedKey].sort().join('|');
    const info = new TextEncoder().encode(`veil-demo-v2|aesgcm|${sortedPublicKeys}|${conversationId}`);
    return { peerUserId: peer.userId, hkdfBase, info };
  }

  async function context(conversationId) {
    const cached = contexts.get(conversationId);
    if (cached) return cached;
    let built = null;
    try {
      built = await buildContext(conversationId);
    } catch (error) {
      console.warn('envelope key unavailable', error);
    }
    if (built) contexts.set(conversationId, built);
    return built;
  }

  function messageKey(ctx, nonce) {
    return subtle.deriveKey(
      { name: 'HKDF', hash: 'SHA-256', salt: nonce, info: ctx.info },
      ctx.hkdfBase,
      { name: 'AES-GCM', length: 256 },
      false,
      ['encrypt', 'decrypt'],
    );
  }

  function assertNotFrozen(ctx) {
    if (directory.pendingChange(ctx.peerUserId)) throw new PeerKeyChangedError(ctx.peerUserId);
  }

  return {
    // Resolves the conversation key ahead of a send (before uploading an
    // attachment, say). False when the peer key cannot be fetched yet.
    async ensureSendable(conversationId) {
      const ctx = await context(conversationId);
      if (ctx) assertNotFrozen(ctx);
      return ctx !== null;
    },

    async encrypt(conversationId, plaintext) {
      const ctx = await context(conversationId);
      if (!ctx) return null;
      assertNotFrozen(ctx);
      const nonce = crypto.getRandomValues(new Uint8Array(NONCE_BYTES));
      const key = await messageKey(ctx, nonce);
      const additionalData = buildAad({ conversationId, senderDeviceId: getSelf()?.deviceId ?? '' });
      const sealed = await subtle.encrypt(
        { name: 'AES-GCM', iv: nonce, additionalData },
        key,
        new TextEncoder().encode(plaintext),
      );
      return { ciphertext: CIPHERTEXT_PREFIX + encodeBase64Url(sealed), nonce: encodeBase64Url(nonce) };
    },

    // Resolves to { payload } (the decrypted UTF-8 string) or
    // { failure: 'legacy' | 'no-key' | 'failed' }.
    async decrypt({ conversationId, ciphertext, nonce, senderDeviceId }) {
      if (typeof ciphertext !== 'string' || !ciphertext.startsWith(CIPHERTEXT_PREFIX)) {
        return { failure: 'legacy' };
      }
      const ctx = await context(conversationId);
      if (!ctx) return { failure: 'no-key' };
      let iv;
      let sealed;
      try {
        iv = decodeBase64Url(nonce);
        sealed = decodeBase64Url(ciphertext.slice(CIPHERTEXT_PREFIX.length));
      } catch {
        return { failure: 'failed' };
      }
      const key = await messageKey(ctx, iv);
      const candidates = senderDeviceId
        ? [{ name: 'AES-GCM', iv, additionalData: buildAad({ conversationId, senderDeviceId }) }, { name: 'AES-GCM', iv }]
        : [{ name: 'AES-GCM', iv }];
      for (const params of candidates) {
        try {
          return { payload: new TextDecoder().decode(await subtle.decrypt(params, key, sealed)) };
        } catch {
          // Try the pre-AAD form next.
        }
      }
      return { failure: 'failed' };
    },

    // Called after the user accepted a peer's new key.
    forgetPeer(userId) {
      for (const [conversationId, ctx] of contexts) {
        if (ctx.peerUserId === userId) contexts.delete(conversationId);
      }
    },

    reset() {
      contexts.clear();
    },
  };
}
