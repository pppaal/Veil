// Read-only support for the web demo's retired 'veil-envelope-v1-dev'
// envelopes, so history written by earlier builds stays readable while the
// identity that wrote it is kept. Nothing produces this format any more.
//   ciphertext = "v2." + base64url(AES-256-GCM(key, iv = nonce, aad))
//   key        = HKDF-SHA256(ikm = X25519(myX, peerX), salt = nonce,
//                  info = "veil-demo-v2|aesgcm|" + sorted(myXPub, peerXPub) + "|" + conversationId)
//   aad        = buildAad({ conversationId, senderDeviceId }); messages from
//                before the AAD binding decrypt without it.
// One static secret per peer pair: no forward secrecy, no replay protection,
// and either party could have written any message. Content read here is
// always shown as legacy and unauthenticated.

import { buildAad } from '../../lib/aad.js';
import { decodeBase64Url } from '../core/base64url.js';

const LEGACY_V1DEV_VERSION = 'veil-envelope-v1-dev';
const CIPHERTEXT_PREFIX = 'v2.';

export const isLegacyV1DevEnvelope = (envelope) => envelope?.version === LEGACY_V1DEV_VERSION;

// getSelf() -> the legacy identity record ({ xPrivKey, xPubB64u }) or null;
// peerKey(conversationId) -> the peer's X25519 key pinned by an earlier
// build, or null.
export function createLegacyV1DevReader({ subtle, getSelf, peerKey }) {
  async function context(conversationId) {
    const self = getSelf();
    const peerPublicB64u = self?.xPrivKey ? await peerKey(conversationId) : null;
    if (!peerPublicB64u) return null;
    const peerPublic = await subtle.importKey('raw', decodeBase64Url(peerPublicB64u), { name: 'X25519' }, false, []);
    const shared = await subtle.deriveBits({ name: 'X25519', public: peerPublic }, self.xPrivKey, 256);
    const hkdfBase = await subtle.importKey('raw', shared, 'HKDF', false, ['deriveKey']);
    const sortedPublicKeys = [self.xPubB64u, peerPublicB64u].sort().join('|');
    const info = new TextEncoder().encode(`veil-demo-v2|aesgcm|${sortedPublicKeys}|${conversationId}`);
    return { hkdfBase, info };
  }

  return {
    // Resolves to { payload } (the decrypted UTF-8 string) or
    // { failure: 'legacy' | 'no-key' | 'failed' }.
    async decrypt({ conversationId, ciphertext, nonce, senderDeviceId }) {
      if (typeof ciphertext !== 'string' || !ciphertext.startsWith(CIPHERTEXT_PREFIX)) return { failure: 'legacy' };
      let ctx;
      try {
        ctx = await context(conversationId);
      } catch {
        ctx = null;
      }
      if (!ctx) return { failure: 'no-key' };
      let iv;
      let sealed;
      try {
        iv = decodeBase64Url(nonce);
        sealed = decodeBase64Url(ciphertext.slice(CIPHERTEXT_PREFIX.length));
      } catch {
        return { failure: 'failed' };
      }
      const key = await subtle.deriveKey(
        { name: 'HKDF', hash: 'SHA-256', salt: iv, info: ctx.info },
        ctx.hkdfBase,
        { name: 'AES-GCM', length: 256 },
        false,
        ['decrypt'],
      );
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
  };
}
