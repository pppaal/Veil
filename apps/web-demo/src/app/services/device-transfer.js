// Device transfer, both sides (src/features/device-transfer.js). The OLD
// device opens a transfer session, watches it for the new device's claim and
// approves it once the user has compared fingerprints; the server revoking
// this device is how the completion arrives here. The NEW device, which has
// no session yet, generates a fresh identity, claims the session with a
// proof signed by it, and retries /device-transfer/complete with one
// completion proof until the old device has approved.

import { generateIdentity, publishedKeys, signChallenge } from '../../crypto/identity.js';
import {
  encodeTransferCode,
  storeTransferredIdentity,
  transferFingerprint,
  TRANSFER_POLL_MS,
  watchOldDeviceTransfer,
} from '../../features/device-transfer.js';

const delay = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

// session: src/app/services/session.js.
export function createDeviceTransfer({ store, stack, session }) {
  let watched = null;

  return {
    // Old device. Opens a session, which closes any earlier one on the
    // server, and watches it. Resolves to { code, transfer }, the code for
    // the new device and the watch (outcome, approve(), cancel(), approved).
    async start({ onClaim, onPollError }) {
      const init = await stack.authedApi('/device-transfer/init', { method: 'POST', body: { oldDeviceId: store.state.me.deviceId } });
      const transfer = watchOldDeviceTransfer({ sessionId: init.sessionId, authedApi: stack.authedApi, onClaim, onPollError });
      watched = transfer;
      return { code: encodeTransferCode(init), transfer };
    },

    current: () => watched,

    // Forgets the watch once its outcome is in, unless a newer one replaced it.
    settled(transfer) {
      if (watched === transfer) watched = null;
    },

    stop() {
      watched?.cancel();
      watched = null;
    },

    // For a rejected session: 'completed' when the rejection is the approved
    // transfer going through (src/features/device-transfer.js sessionEnded).
    sessionEnded: async () => watched?.sessionEnded(),

    // New device. A fresh identity, its published keys, and the fingerprint
    // the old device will show for them.
    async newIdentity() {
      const keys = await generateIdentity(crypto.subtle, { nowMs: stack.apiClient.serverNow() });
      const published = await publishedKeys(crypto.subtle, keys);
      return { keys, published, fingerprint: await transferFingerprint(crypto.subtle, published) };
    },

    // Claims the session from the code; resolves to the claim id.
    async claim({ sessionId, transferToken }, { name, keys, published }) {
      const authProof = await signChallenge(crypto.subtle, keys.edPrivKey, `transfer-claim:${sessionId}:${transferToken}`);
      const claim = await stack.api('/device-transfer/claim', {
        method: 'POST',
        body: { sessionId, transferToken, newDeviceName: name, platform: 'android', ...published, authProof },
      });
      return claim.claimId;
    },

    // Retries /complete with one proof until the old device has approved.
    // Resolves to the completion, or to null once waiting() turns false;
    // throws on any refusal other than "not approved yet".
    async awaitCompletion({ sessionId, transferToken, claimId, keys }, { waiting, onWaiting }) {
      const authProof = await signChallenge(crypto.subtle, keys.edPrivKey, `transfer-complete:${sessionId}:${claimId}:${transferToken}`);
      while (waiting()) {
        try {
          return await stack.api('/device-transfer/complete', { method: 'POST', body: { sessionId, transferToken, claimId, authProof } });
        } catch (error) {
          if (error.code !== 'transfer_approval_required' && error.status !== 403) throw error;
          onWaiting();
          await delay(TRANSFER_POLL_MS);
        }
      }
      return null;
    },

    // Stores the identity the completion activated; then clears what an
    // identity it replaced left here. Resolves to { cleanupError }.
    storeIdentity: ({ completion, keys, replacesIdentity }) => storeTransferredIdentity({
      completion,
      keys,
      sessionStore: stack.sessionStore,
      clearReplacedIdentity: replacesIdentity ? session.clearReplacedIdentity : null,
    }),
  };
}
