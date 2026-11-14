// Everything this device sends into a conversation: text, reactions, edits
// and deletions. Content is sealed end to end (src/features/sender.js) and
// shown at once as a pending bubble, then delivered; a send that cannot go
// out now waits, sealed, in the outbound queue. Under a disappearing timer
// its expiry is sealed in with it, stamped on the expiry clock
// (src/core/expiry.js expiryNow), which is the relay's give or take an hour.

import { t } from '../../../i18n/i18n.js';
import { expiryNow } from '../../core/expiry.js';
import { MESSAGE_MAX_CHARS } from '../../domain/composer-text.js';
import { disappearingExpiry, textContent } from '../../domain/content.js';
import { isTextKind } from '../../domain/ingest.js';
import { isPendingId, pendingId } from '../../domain/local-messages.js';
import { reactionsByTarget } from '../../domain/reactions.js';
import { LegacyIdentityError, PeerKeyChangedError, PeerUnavailableError } from '../../features/secure-messaging.js';
import { newClientMessageId } from '../../features/sender.js';
import { serializeMessageForCache } from '../../platform/persist.js';

// Local-only state of a bubble shown before its content was sealed (an
// upload's preview, a recording), carried over to the sent message.
const LOCAL_MEDIA_FIELDS = ['_imageUrl', '_voiceUrl', '_localFile'];

// realtime: src/app/services/realtime.js (typing); onSent() when a text was
// sealed; toast(message, kind).
export function createSend({ store, stack, messages, realtime, onSent, toast }) {
  const { state } = store;

  // A frozen conversation gets the explanation of why, not a generic error.
  function reportFailure(label, error) {
    if (error instanceof PeerKeyChangedError) {
      // A key refused outright (declined, or a device of another contact)
      // leaves no change to review at the top of the chat.
      toast(t(stack.trust.pendingChange(error.userId) ? 'keyChange.sendBlocked' : 'keyChange.sendRefused'), 'error');
    } else if (error instanceof PeerUnavailableError) {
      toast(t(error.reason === 'not-upgraded' ? 'peer.notUpgraded' : 'peer.unavailable'), 'error');
    } else if (error instanceof LegacyIdentityError) {
      toast(t('legacy.composerFrozen'), 'error');
    } else {
      toast(`${label}: ${error?.message || 'unknown'}`, 'error');
    }
  }

  // `local` is a bubble already shown for this send (an upload in
  // progress). Resolves to the delivered view, or null.
  async function sendContent(conv, unsealed, {
    clientMessageId = newClientMessageId(),
    attachmentId = null,
    failureLabel = '전송 실패',
    local = null,
    onSealed = () => {},
  } = {}) {
    const content = { ...unsealed, expiresAt: disappearingExpiry(conv.disappearingTimerSeconds, expiryNow()) };
    const markFailed = (message) => {
      message._status = 'failed';
      store.notify('panels');
    };
    let envelope;
    try {
      envelope = await stack.sender.seal(conv.id, content, { clientMessageId, attachmentId });
    } catch (error) {
      reportFailure(failureLabel, error);
      if (local) markFailed(local);
      return null;
    }
    onSealed();
    const optimistic = await messages.ingest({
      id: pendingId(clientMessageId),
      clientMessageId,
      conversationId: conv.id,
      senderDeviceId: state.me.deviceId,
      ciphertext: envelope.ciphertext,
      nonce: envelope.nonce,
      messageType: envelope.messageType,
      serverReceivedAt: null,
    }, { content });
    for (const field of LOCAL_MEDIA_FIELDS) if (local?.[field] !== undefined) optimistic[field] = local[field];
    optimistic._status = 'pending';
    optimistic._localAt = local?._localAt ?? new Date().toISOString();
    store.putOwnMessage(conv.id, clientMessageId, optimistic);
    store.notify('panels');

    let delivered;
    try {
      delivered = await stack.sender.deliver({ conversationId: conv.id, clientMessageId, envelope });
    } catch (error) {
      // Refused for good: the sealed envelope stays with the bubble, in
      // memory only, for Retry to queue again (src/app/services/outbox.js).
      optimistic._envelope = envelope;
      markFailed(optimistic);
      toast(`${failureLabel}: ${error.message}`, 'error');
      return null;
    }
    if (delivered.queued) {
      if (!delivered.sessionEnded) toast('연결 안 됨 — 큐잉 후 자동 재시도합니다');
      return null;
    }
    const view = await messages.ingest(delivered.message, { previous: optimistic });
    for (const field of LOCAL_MEDIA_FIELDS) if (optimistic[field] !== undefined) view[field] ??= optimistic[field];
    store.putOwnMessage(conv.id, clientMessageId, view);
    conv.lastMessage = view;
    messages.sortConversations();
    messages.persistMessage(view);
    messages.persistConversation(conv);
    store.notify('panels', 'sidebar');
    return view;
  }

  return {
    reportFailure,
    sendContent,

    // A text, as the answer to the conversation's reply draft if there is
    // one. onSealed() runs once it is sealed, to clear the composer.
    async sendText(convId, text, { onSealed = () => {} } = {}) {
      if (!text || !convId) return;
      if (text.length > MESSAGE_MAX_CHARS) {
        toast(`메시지가 너무 길어요 (최대 ${MESSAGE_MAX_CHARS.toLocaleString()}자)`, 'error');
        return;
      }
      const conv = store.conversation(convId);
      if (!conv) return;
      const replyToId = state.replyDrafts.get(convId)?.id ?? null;
      await sendContent(conv, textContent(text, replyToId), {
        onSealed: () => {
          if (replyToId) state.replyDrafts.delete(convId);
          onSealed();
          realtime.stopTyping(convId);
          onSent();
        },
      });
    },

    // Reactions are end-to-end encrypted control messages
    // (src/domain/reactions.js); the same emoji again takes ours back.
    async react(messageId, emoji) {
      // A message the server has not named yet cannot be a reaction's target.
      const found = isPendingId(messageId) ? null : store.locateMessage(messageId);
      if (!found) return;
      const current = reactionsByTarget(found.list).get(messageId)
        ?.find((reaction) => reaction.senderDeviceId === state.me.deviceId)?.emoji ?? null;
      const clientMessageId = newClientMessageId();
      try {
        const conv = store.conversation(found.convId);
        const { content, message } = await stack.sender.react({
          conversationId: found.convId,
          clientMessageId,
          target: messageId,
          emoji,
          current,
          expiresAt: disappearingExpiry(conv?.disappearingTimerSeconds, expiryNow()),
        });
        // A queued reaction shows once the outbound queue delivers it.
        if (!message) return;
        const view = await messages.ingest(message, { content });
        store.putOwnMessage(found.convId, clientMessageId, view);
        messages.persistMessage(view);
        store.notify('panels');
      } catch (error) {
        reportFailure('반응 실패', error);
      }
    },

    // An edit is a new frame on the session; the stored content is replaced
    // only once the server has taken it, and it keeps the message's expiry:
    // an edit can never make a message last longer.
    async edit(message, convId, newText) {
      const content = { ...textContent(newText, message.replyTo), expiresAt: message.expiresAtMs ?? null };
      try {
        const envelope = await stack.secure.sealEdit(convId, content);
        await stack.authedApi(`/messages/${message.id}`, {
          method: 'PATCH',
          body: { ciphertext: envelope.ciphertext, nonce: envelope.nonce, version: envelope.version },
        });
        await stack.secure.rememberEdit(convId, message.id, content, envelope.nonce);
        const edited = Object.assign(serializeMessageForCache(message), {
          ciphertext: envelope.ciphertext,
          nonce: envelope.nonce,
          editedAt: new Date().toISOString(),
        });
        await messages.reingestInPlace(message.id, edited, { content, editCount: (message.editCount || 0) + 1 });
      } catch (error) {
        reportFailure('수정 실패', error);
      }
    },

    // Tombstones the message on the server. Resolves to what an undo can put
    // back in the composer, { convId, text } for a text, captured before the
    // tombstone replaces it; null otherwise.
    async deleteMessage(messageId) {
      const found = store.locateMessage(messageId);
      const captured = found && isTextKind(found.message.kind)
        ? { convId: found.convId, text: found.message.displayText }
        : null;
      try {
        await stack.authedApi(`/messages/${messageId}`, { method: 'DELETE' });
      } catch (error) {
        toast('삭제 실패: ' + error.message, 'error');
      }
      return captured;
    },
  };
}
