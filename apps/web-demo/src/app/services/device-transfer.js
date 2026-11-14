// Device transfer, both sides (src/features/device-transfer.js). The OLD
// device opens a transfer session, watches it for the new device's claim and
// approves it, signed with its auth key, once the user has compared
// fingerprints; the server revoking this device is how the completion
// arrives here. The NEW device, which has no session yet, generates a fresh
// identity, claims the session with a proof signed by it, and sends
// /device-transfer/complete with one completion proof until the old device
// has approved (contract C-TRANSFER-RETRY, awaitCompletion).

import { generateIdentity, publishedKeys, signChallenge } from '../../crypto/identity.js';
import { WEB_DEVICE_PLATFORM } from '../../domain/web-device.js';
import {
  encodeTransferCode,
  storeTransferredIdentity,
  transferFingerprint,
  TRANSFER_POLL_MS,
  watchOldDeviceTransfer,
} from '../../features/device-transfer.js';
import { ApiError } from '../../platform/api-client.js';

const delay = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

// A /complete that failed with no answer from the relay (the network) or
// with the relay failing (5xx) may have gone through. The relay answers an
// identical retry of a completion that went through with that completion.
const outcomeUnknown = (error) => !(error instanceof ApiError) || error.status >= 500;

// session: src/app/services/session.js; sleep(ms) waits between attempts.
export function createDeviceTransfer({ store, stack, session, sleep = delay }) {
  let watched = null;

  return {
    // Old device. Opens a session, which closes any earlier one on the
    // server, and watches it. Resolves to { code, transfer }, the code for
    // the new device and the watch (outcome, approve(), cancel(), approved).
    async start({ onClaim, onPollError }) {
      const init = await stack.authedApi('/device-transfer/init', { method: 'POST', body: { oldDeviceId: store.state.me.deviceId } });
      const transfer = watchOldDeviceTransfer({
        sessionId: init.sessionId,
        authedApi: stack.authedApi,
        signApproval: async (challenge) => {
          const credentials = await stack.sessionStore.getDeviceCredentials();
          if (!credentials) throw new Error('no device key to sign the approval with');
          return credentials.sign(challenge);
        },
        onClaim,
        onPollError,
      });
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
        body: { sessionId, transferToken, newDeviceName: name, platform: WEB_DEVICE_PLATFORM, ...published, authProof },
      });
      return claim.claimId;
    },

    // Sends /complete, the same request with one proof each time, until it
    // answers. Polls while the old device has not approved
    // (transfer_approval_required) and waiting() holds. After a network
    // failure or a 5xx it sends the same request again whatever waiting()
    // says: that completion may have gone through, and then these keys are
    // the identity's only copy. Resolves to the completion, or to null once
    // waiting() turns false while the relay says it is not approved yet;
    // throws on any other refusal (transfer_session_inactive, any other
    // 4xx), which leaves the keys with the caller.
    async awaitCompletion({ sessionId, transferToken, claimId, keys }, { waiting, onWaiting, onRetrying = () => {} }) {
      const authProof = await signChallenge(crypto.subtle, keys.edPrivKey, `transfer-complete:${sessionId}:${claimId}:${transferToken}`);
      let unanswered = false;
      while (unanswered || waiting()) {
        try {
          return await stack.api('/device-transfer/complete', { method: 'POST', body: { sessionId, transferToken, claimId, authProof } });
        } catch (error) {
          if (error?.code === 'transfer_approval_required') {
            unanswered = false;
            if (!waiting()) return null;
            onWaiting();
          } else if (outcomeUnknown(error)) {
            unanswered = true;
            onRetrying(error);
          } else {
            throw error;
          }
        }
        await sleep(TRANSFER_POLL_MS);
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
