// Every outgoing message, reactions included, goes out the same way: content
// sealed end to end (src/features/secure-messaging.js), then POST /messages
// with nothing but the envelope. The envelope - never the plaintext - is in
// the outbound queue before the request goes out, so a tab closed, reloaded
// or crashed while it is in flight loses nothing, and stays there when the
// send fails for a reason that can pass (network, 5xx, 429, an ended
// session); the session state it was sealed under is already committed, so
// it is sent exactly as it was sealed. The server takes a repeat of the
// same client message id as the same message.

import { retryDelayMs } from '../domain/delivery.js';
import { AuthError } from '../platform/api-client.js';
import { outboundQueueEntry } from '../platform/persist.js';
import { reactionContent } from '../domain/content.js';
import { toggledReaction } from '../domain/reactions.js';

const isRetryableSendError = (error) =>
  error instanceof AuthError || !error?.status || error.status >= 500 || error.status === 429;

// A send's idempotency key. The server keeps it beside the ciphertext for as
// long as the message, so it is random (a UUID v4) and says nothing about
// when the message was written or what kind it is.
export const newClientMessageId = () => crypto.randomUUID();

// queue: { put(entry), delete(clientMessageId) } over the 'outbound' store.
export function createSender({ secure, authedApi, queue, clock = Date.now }) {
  // Client message ids whose POST this tab has in flight: the outbox skips
  // them however long the request takes, so a slow request is not sent a
  // second time from the same tab while it is still on its way.
  const inFlight = new Set();

  // { envelope } for the conversation, with the outer attachment pointer
  // carrying only the blob's id (contract C3).
  async function seal(conversationId, content, { clientMessageId, attachmentId = null }) {
    const envelope = await secure.seal(conversationId, content, { clientMessageId });
    if (attachmentId) envelope.attachment = { attachmentId };
    return envelope;
  }

  // Resolves to { message } once the server has the message, or
  // { queued: true, sessionEnded } when it will go out later; throws on a
  // permanent refusal, which leaves nothing queued. While the request is in
  // flight this tab's outbox skips its queue entry (isInFlight), and the
  // entry is not due for a short while, which keeps other tabs from sending
  // it meanwhile; once that wait passes with no tab sending it (the page was
  // closed), the next drain sends it.
  async function deliver({ conversationId, clientMessageId, envelope }) {
    const entry = outboundQueueEntry({ clientMessageId, conversationId, envelope });
    inFlight.add(clientMessageId);
    try {
      await queue.put({ ...entry, nextRetryAt: clock() + retryDelayMs(1) });
      let message;
      try {
        ({ message } = await authedApi('/messages', {
          method: 'POST',
          body: { conversationId, clientMessageId, envelope },
        }));
        await secure.acknowledge(message);
      } catch (error) {
        if (!isRetryableSendError(error)) {
          await queue.delete(clientMessageId);
          throw error;
        }
        await queue.put(entry);
        return { queued: true, sessionEnded: error instanceof AuthError };
      }
      // Delivered: an entry a failed delete leaves behind is sent once more,
      // and the server answers with this same message.
      await queue.delete(clientMessageId).catch(() => {});
      return { message };
    } finally {
      inFlight.delete(clientMessageId);
    }
  }

  return {
    seal,
    deliver,

    // Whether this tab's POST of that send is still on its way.
    isInFlight: (clientMessageId) => inFlight.has(clientMessageId),

    // A reaction is a message like any other: messageType 'reaction', its
    // target and emoji inside the ciphertext, and expiresAt (ms) sealed in
    // under a disappearing timer.
    async react({ conversationId, clientMessageId, target, emoji, current, expiresAt = null }) {
      const content = { ...reactionContent(toggledReaction({ target, emoji, current })), expiresAt };
      const envelope = await seal(conversationId, content, { clientMessageId });
      return { content, ...(await deliver({ conversationId, clientMessageId, envelope })) };
    },
  };
}
