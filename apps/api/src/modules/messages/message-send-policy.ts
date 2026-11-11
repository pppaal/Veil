import {
  ENVELOPE_VERSION_FAMILY,
  PRODUCTION_FORBIDDEN_ATTACHMENT_HINTS,
  PRODUCTION_FORBIDDEN_ENVELOPE_VERSIONS,
  type ConversationType,
} from '@veil/shared';

import { apiError } from '../../common/errors/api-error';

// Clock skew allowance for a client-stamped expiry that is already due.
const EXPIRES_AT_PAST_TOLERANCE_MS = 60_000;
// Matches the longest disappearing timer; beyond it the relay would just be
// long-term storage with extra steps.
const EXPIRES_AT_MAX_AHEAD_MS = 30 * 24 * 60 * 60 * 1000;
// Slack before an expiry past the conversation timer is clamped, so a sender
// whose clock runs a little fast keeps its own authenticated value.
const TIMER_CLAMP_GRACE_MS = 300_000;

export interface EnvelopeAcceptanceInput {
  version: string;
  attachment?: { encryption?: { algorithmHint?: string } | null } | null;
}

/**
 * Rejects envelopes a conversation must not carry: development crypto
 * markers on a production relay, and any version outside the
 * conversation's family. A Sender Keys group accepts only veil-group-v1, so a
 * member cannot fall back to a pairwise format the others would decrypt
 * under weaker assumptions.
 */
export const assertEnvelopeAccepted = (
  conversation: { type: ConversationType; groupUseSenderKeys: boolean },
  envelope: EnvelopeAcceptanceInput,
  isProduction: boolean,
): void => {
  if (isProduction) {
    const hint = envelope.attachment?.encryption?.algorithmHint;
    if (
      PRODUCTION_FORBIDDEN_ENVELOPE_VERSIONS.includes(envelope.version) ||
      (hint !== undefined && PRODUCTION_FORBIDDEN_ATTACHMENT_HINTS.includes(hint))
    ) {
      throw apiError(
        'envelope_version_forbidden',
        'Development envelope formats are not accepted by this relay',
      );
    }
  }

  const family =
    conversation.type === 'group' && conversation.groupUseSenderKeys ? 'group' : 'direct';
  if (!ENVELOPE_VERSION_FAMILY[family].includes(envelope.version)) {
    throw apiError(
      'envelope_version_mismatch',
      `Envelope version ${envelope.version} is not accepted in this conversation`,
    );
  }
};

/**
 * Decides the outer expiresAt the relay stores. The outer value is not
 * authenticated (protocol v2 keeps the real expiry in the inner payload and
 * clients expire at the earlier of the two), so the relay is free to fill it
 * in from the conversation timer and to clamp values that would outlive it.
 */
export const resolveExpiresAt = (
  requested: string | null | undefined,
  timerSeconds: number | null,
  now: Date,
): Date | null => {
  const timerExpiry = timerSeconds ? new Date(now.getTime() + timerSeconds * 1000) : null;
  if (!requested) {
    return timerExpiry;
  }

  const expiresAt = new Date(requested);
  if (Number.isNaN(expiresAt.getTime())) {
    throw apiError('validation_failed', 'expiresAt must be an ISO-8601 timestamp');
  }
  if (expiresAt.getTime() < now.getTime() - EXPIRES_AT_PAST_TOLERANCE_MS) {
    throw apiError('validation_failed', 'expiresAt is in the past');
  }
  if (expiresAt.getTime() > now.getTime() + EXPIRES_AT_MAX_AHEAD_MS) {
    throw apiError('validation_failed', 'expiresAt is more than 30 days ahead');
  }
  if (timerExpiry && expiresAt.getTime() > timerExpiry.getTime() + TIMER_CLAMP_GRACE_MS) {
    return timerExpiry;
  }
  return expiresAt;
};
