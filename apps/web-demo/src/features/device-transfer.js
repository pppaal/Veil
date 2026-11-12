// Device transfer. The old device's side, watchOldDeviceTransfer: poll the
// transfer session, surface the new device's claim for approval, and work out
// how the transfer ended. The new device's side ends in
// storeTransferredIdentity, below.
//
// `outcome` resolves to one of
//   'completed'      the handle now lives on the new device; this copy of the
//                    identity is spent
//   'expired'        the session ran out before the new device completed
//   'closed'         the server closed the session without a transfer (a
//                    newer transfer replaced it, a second claim invalidated
//                    it, or it was swept after expiring)
//   'session-ended'  this device's session was rejected with no approval given
//   'cancelled'      the app stopped watching
//
// The server revokes the old device in the same transaction that completes
// the transfer, so this device never gets to read the 'completed' status of
// its own transfer: from then on every request it makes is refused and its
// session is rejected. Completion therefore reaches the old device as its
// session ending after the user approved the claim. That trusts the server
// no further than before (it could always answer 'completed'), and with no
// approval given a rejected session stays a rejected session that keeps the
// identity.

import { decodeBase64Url } from '../core/base64url.js';
import { concatBytes, toHex } from '../crypto/bytes.js';
import { sha256 } from '../crypto/keys.js';
import { AuthError } from '../platform/api-client.js';

export const TRANSFER_POLL_MS = 2500;

// The code the old device shows and the new one pastes: the session and its
// token as unpadded base64 of their JSON.
export const encodeTransferCode = ({ sessionId, transferToken }) =>
  btoa(JSON.stringify({ sessionId, transferToken })).replace(/=+$/, '');

// { sessionId, transferToken } from a pasted code, or null when it is not one.
export function parseTransferCode(code) {
  try {
    const parsed = JSON.parse(atob(code + '='.repeat((4 - (code.length % 4)) % 4)));
    return parsed?.sessionId && parsed.transferToken
      ? { sessionId: parsed.sessionId, transferToken: parsed.transferToken }
      : null;
  } catch {
    return null;
  }
}

// What the old device shows for a claim: SHA-256 over the auth key and the
// identity key the new device will be trusted with, in groups of four hex
// digits, computed the way the server computes claimantFingerprint.
export async function transferFingerprint(subtle, { authPublicKey, publicIdentityKey }) {
  const digest = await sha256(subtle, concatBytes([decodeBase64Url(authPublicKey), decodeBase64Url(publicIdentityKey)]));
  return toHex(digest).replace(/(.{4})(?!$)/g, '$1 ');
}

const delay = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

export function watchOldDeviceTransfer({
  sessionId,
  authedApi,
  onClaim,
  onPollError,
  sleep = delay,
  pollMs = TRANSFER_POLL_MS,
}) {
  let claim = null;
  // The approve request from the moment the user confirms; dropped again if
  // it fails, so the user can retry and a failed approval counts for nothing.
  let approval = null;
  let completedReads = 0;
  let outcome = null;
  let resolveOutcome;
  const settled = new Promise((resolve) => { resolveOutcome = resolve; });

  function settle(result) {
    outcome ??= result;
    resolveOutcome(outcome);
    return outcome;
  }

  // An approval still in flight counts once it lands: the new device can
  // complete, revoking this one, before the approve response arrives here.
  const hasApproved = async () => (approval ? approval.catch(() => false) : false);

  async function sessionEnded() {
    if (outcome) return outcome;
    return settle((await hasApproved()) ? 'completed' : 'session-ended');
  }

  async function read(status) {
    switch (status.status) {
      case 'expired':
        settle('expired');
        return;
      case 'invalidated':
        settle('closed');
        return;
      case 'completed':
        // Reading this at all means this device still has a working session,
        // so the server closed the session without revoking it. The one
        // exception is a completion that commits between the server's auth
        // check and this read; after an approval one more poll tells the two
        // apart, since that poll is refused if the transfer went through.
        if (completedReads++ > 0 || !(await hasApproved())) settle('closed');
        return;
      default:
        if (status.pendingClaim && !claim) {
          claim = status.pendingClaim;
          onClaim?.(claim);
        }
    }
  }

  (async () => {
    while (!outcome) {
      try {
        const status = await authedApi(`/device-transfer/sessions/${encodeURIComponent(sessionId)}`);
        if (!outcome) await read(status);
      } catch (error) {
        if (error instanceof AuthError) await sessionEnded();
        else if (!outcome) onPollError?.(error);
      }
      if (!outcome) await sleep(pollMs);
    }
  })();

  return {
    outcome: settled,

    // True from the moment the user's approval is sent until it fails. The
    // server cannot call off an approved transfer, so from then on the app
    // keeps watching even if the user closes the dialog.
    get approved() {
      return approval !== null;
    },

    approve() {
      if (!claim) return Promise.reject(new Error('no claim to approve'));
      const request = authedApi('/device-transfer/approve', {
        method: 'POST',
        body: { sessionId, claimId: claim.claimId },
      }).then(() => true);
      approval = request;
      request.catch(() => {
        if (approval === request) approval = null;
      });
      return request;
    },

    // For the app's onSessionRejected: resolves to 'completed' when the
    // rejection is this transfer going through, else to 'session-ended' (or
    // to the outcome already settled).
    sessionEnded,

    cancel() {
      settle('cancelled');
    },
  };
}

// New device: store the identity a completed transfer activated. By the time
// /device-transfer/complete answers, the server has activated these keys and
// revoked the old device, which then destroys its own copy, so until they are
// saved the keys in memory here are the identity's only copy. They are saved
// first, before anything that can fail or wait, and clearing what a replaced
// identity left in this browser runs after as best effort: its failure is
// returned for the caller to report, never allowed to cost the new identity.
// A failed save throws with nothing else touched, so the caller keeps the
// keys and can call this again.
export async function storeTransferredIdentity({ completion, keys, sessionStore, clearReplacedIdentity = null }) {
  // The private keys are non-extractable CryptoKeys, stored by structured
  // clone. /complete does not name the user; every login records it
  // (session-store saveTokens).
  await sessionStore.save({
    handle: completion.handle,
    userId: null,
    deviceId: completion.newDeviceId,
    ...keys,
    accessToken: null,
    refreshToken: null,
  });
  try {
    await clearReplacedIdentity?.();
    return { cleanupError: null };
  } catch (cleanupError) {
    return { cleanupError };
  }
}
