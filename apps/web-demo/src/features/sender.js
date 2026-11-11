// Every outgoing message, reactions included, goes out the same way: content
// sealed end to end (src/features/secure-messaging.js), then POST /messages
// with nothing but the envelope. When the send fails for a reason that can
// pass (network, 5xx, 429, an ended session), the envelope - never the
// plaintext - waits in the outbound queue; the session state it was sealed
// under is already committed, so it is sent exactly as it was sealed.

import { AuthError } from '../platform/api-client.js';
import { outboundQueueEntry } from '../platform/persist.js';
import { reactionContent } from '../domain/content.js';
import { toggledReaction } from '../domain/reactions.js';

const isRetryableSendError = (error) =>
  error instanceof AuthError || !error?.status || error.status >= 500 || error.status === 429;

// queue: { put(entry) } over the 'outbound' store.
export function createSender({ secure, authedApi, queue }) {
  // { envelope } for the conversation, with the outer attachment pointer
  // carrying only the blob's id (contract C3).
  async function seal(conversationId, content, { clientMessageId, attachmentId = null }) {
    const envelope = await secure.seal(conversationId, content, { clientMessageId });
    if (attachmentId) envelope.attachment = { attachmentId };
    return envelope;
  }

  // Resolves to { message } once the server has the message, or
  // { queued: true, sessionEnded } when it will go out later; throws on a
  // permanent refusal.
  async function deliver({ conversationId, clientMessageId, envelope }) {
    try {
      const { message } = await authedApi('/messages', {
        method: 'POST',
        body: { conversationId, clientMessageId, envelope },
      });
      await secure.acknowledge(message);
      return { message };
    } catch (error) {
      if (!isRetryableSendError(error)) throw error;
      await queue.put(outboundQueueEntry({ clientMessageId, conversationId, envelope }));
      return { queued: true, sessionEnded: error instanceof AuthError };
    }
  }

  return {
    seal,
    deliver,

    // A reaction is a message like any other: messageType 'reaction', its
    // target and emoji inside the ciphertext.
    async react({ conversationId, clientMessageId, target, emoji, current }) {
      const content = reactionContent(toggledReaction({ target, emoji, current }));
      const envelope = await seal(conversationId, content, { clientMessageId });
      return { content, ...(await deliver({ conversationId, clientMessageId, envelope })) };
    },
  };
}
