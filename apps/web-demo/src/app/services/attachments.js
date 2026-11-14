// Images, voice notes and files: shown at once as a local bubble, sealed
// under a fresh key (src/crypto/attachment-v2.js) and uploaded as an opaque
// blob, then sent as a message whose end-to-end encrypted content carries
// the pointer (key, digest, type, size). The relay sees only the blob and
// its id.

import { encryptAttachment } from '../../crypto/attachment-v2.js';
import { toHex } from '../../crypto/bytes.js';
import { sha256 } from '../../crypto/keys.js';
import { mediaContent } from '../../domain/content.js';
import { KIND_LABELS } from '../../domain/payload.js';
import { newClientMessageId } from '../../features/sender.js';

const PENDING_TEXT = {
  image: () => KIND_LABELS.image,
  voice: () => KIND_LABELS.voice,
  file: (name) => `📁 ${name}`,
};

// send: src/app/services/send.js.
export function createAttachments({ store, stack, messages, send }) {
  // The id is ours, proposed with the ticket, because the blob's AAD binds it.
  async function upload(blob, contentType) {
    const attachmentId = crypto.randomUUID();
    const plaintext = new Uint8Array(await blob.arrayBuffer());
    const sealed = await encryptAttachment(crypto.subtle, stack.keySource.randomBytes, { attachmentId, contentType, plaintext });
    const ticket = await stack.authedApi('/attachments/upload-ticket', {
      method: 'POST',
      body: {
        attachmentId,
        contentType: 'application/octet-stream',
        sizeBytes: sealed.blob.byteLength,
        sha256: toHex(await sha256(crypto.subtle, sealed.blob)),
      },
    });
    if (ticket.attachmentId !== attachmentId) throw new Error('the relay assigned another attachment id');
    const putRes = await fetch(ticket.upload.uploadUrl, { method: 'PUT', headers: ticket.upload.headers, body: sealed.blob });
    if (!putRes.ok) throw new Error(`upload PUT failed: ${putRes.status}`);
    await stack.authedApi('/attachments/complete', { method: 'POST', body: { attachmentId, uploadStatus: 'uploaded' } });
    return sealed.pointer;
  }

  return {
    // kind: 'image', 'voice' or 'file'; local: the bubble's preview fields.
    // Resolves to the delivered view, or null.
    async sendMedia(convId, { kind, blob, contentType, name = '', failureLabel, local }) {
      const conv = store.conversation(convId);
      if (!conv) return null;
      // The session is started (or checked) first, so a frozen conversation
      // never uploads a blob.
      try {
        await stack.secure.prepare(convId);
      } catch (error) {
        send.reportFailure(failureLabel, error);
        return null;
      }
      const clientMessageId = newClientMessageId();
      const pending = Object.assign(messages.pendingLocalMessage({
        clientMessageId,
        conversationId: convId,
        messageType: kind,
        kind,
        displayText: PENDING_TEXT[kind](name),
      }), local);
      store.putOwnMessage(convId, clientMessageId, pending);
      store.notify('panels');
      let pointer;
      try {
        pointer = await upload(blob, contentType);
      } catch (error) {
        send.reportFailure(failureLabel, error);
        pending._status = 'failed';
        store.notify('panels');
        return null;
      }
      return send.sendContent(conv, mediaContent(kind, pointer, name), {
        clientMessageId,
        attachmentId: pointer.id,
        failureLabel,
        local: pending,
      });
    },
  };
}
