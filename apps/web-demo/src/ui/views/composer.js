// The composer under a conversation: the text box with its in-memory
// draft, the reply banner, the send button, the voice button, and the image
// and file pickers (also fed by dropping an image on it).

import { MESSAGE_MAX_CHARS } from '../../domain/composer-text.js';
import { snippetOf } from '../../domain/conversations.js';
import { shownHandle } from '../../domain/handles.js';
import { sanitizeFilename } from '../../domain/sanitize.js';
import { el } from '../dom.js';
import { toast } from '../toast.js';
import { checkImage, confirmImage, IMAGE_ACCEPT, isSendableImageType } from './image-preview.js';

const FILE_MAX_BYTES = 25 * 1024 * 1024;
const MAX_HEIGHT_PX = 140;

const textareaOf = (convId) => document.querySelector(`.panel[data-conv="${convId}"] .panel-input textarea`);

function pickFile(accept, onPicked) {
  const input = el('input', { type: 'file', accept });
  input.addEventListener('change', () => {
    const file = input.files?.[0];
    if (file) onPicked(file);
  });
  input.click();
}

// send: src/app/services/send.js; attachments:
// src/app/services/attachments.js; realtime: src/app/services/realtime.js;
// voice: src/ui/views/voice-recorder.js; sounds: src/ui/sounds.js.
export function createComposer({ store, send, attachments, realtime, voice, sounds }) {
  const { state } = store;

  function saveDraft(convId, text) {
    if (!convId) return;
    if (text) state.drafts.set(convId, text);
    else state.drafts.delete(convId);
  }

  async function sendImage(convId, file) {
    if (!checkImage(file)) return;
    // The local file is the bubble's preview while it uploads.
    const sent = await attachments.sendMedia(convId, {
      kind: 'image',
      blob: file,
      contentType: file.type,
      failureLabel: '이미지 전송 실패',
      local: { _imageUrl: URL.createObjectURL(file) },
    });
    if (sent) sounds.playSend();
  }

  async function sendFile(convId, file) {
    const name = sanitizeFilename(file.name);
    const sent = await attachments.sendMedia(convId, {
      kind: 'file',
      blob: file,
      contentType: file.type || 'application/octet-stream',
      name,
      failureLabel: '파일 전송 실패',
      local: { _localFile: { name, sizeBytes: file.size } },
    });
    if (sent) sounds.playSend();
  }

  const offerImage = (convId, file) => confirmImage(file, () => sendImage(convId, file));

  function pickAnyFile(convId) {
    pickFile(undefined, (file) => {
      if (isSendableImageType(file.type)) {
        offerImage(convId, file);
        return;
      }
      if (file.size > FILE_MAX_BYTES) {
        toast('파일이 25MB 를 초과합니다', 'error');
        return;
      }
      sendFile(convId, file);
    });
  }

  function sendTyped(textarea, convId) {
    return send.sendText(convId, textarea.value.trim(), {
      onSealed: () => {
        textarea.value = '';
        textarea.style.height = 'auto';
        textarea.dispatchEvent(new Event('input'));
      },
    });
  }

  function replyBanner(convId, peerHandle) {
    const draft = state.replyDrafts.get(convId);
    if (!draft) return null;
    return el('div', { class: 'reply-banner' }, [
      el('span', { class: 'reply-banner-icon' }, ['↩']),
      el('div', { class: 'reply-banner-body' }, [
        el('div', { class: 'reply-banner-meta' }, ['답장: @' + shownHandle(draft.sender ?? peerHandle)]),
        el('div', { class: 'reply-banner-snippet' }, [draft.snippet]),
      ]),
      el('button', {
        class: 'reply-banner-close',
        'aria-label': '답장 취소',
        onclick: () => {
          state.replyDrafts.delete(convId);
          store.notify('panels');
        },
      }, ['×']),
    ]);
  }

  function attachButton(className, label, title, glyph, onClick) {
    return el('button', { class: className, 'aria-label': label, title, onclick: onClick }, [el('span', { 'aria-hidden': 'true' }, [glyph])]);
  }

  return {
    // The composer of a conversation; a frozen one takes no text, and its
    // placeholder says why. Returns { node, textarea }.
    render(convId, { frozen, placeholder, peerHandle }) {
      const textarea = el('textarea', { placeholder, rows: '1', 'aria-label': '메시지 입력', maxlength: String(MESSAGE_MAX_CHARS) });
      textarea.disabled = frozen;
      const draft = state.drafts.get(convId);
      if (draft) textarea.value = draft.slice(0, MESSAGE_MAX_CHARS);
      const sendButton = el('button', { class: 'send-btn', 'aria-label': '전송', onclick: () => sendTyped(textarea, convId) }, [
        el('span', { 'aria-hidden': 'true' }, ['↑']),
      ]);
      const voiceButton = voice.button(convId);
      voiceButton.disabled = frozen;
      const fileButton = attachButton('file-btn image-btn', '파일 첨부', '파일 첨부 (PDF / 비디오 / 기타)', '📎', () => pickAnyFile(convId));
      fileButton.style.fontSize = '16px';
      const imageButton = attachButton('image-btn', '이미지 첨부', '이미지 첨부', '📷', () => pickFile(IMAGE_ACCEPT, (file) => offerImage(convId, file)));

      // On every input: grow, send typing, keep the draft. maxlength holds
      // typing back, but a paste can still land over the cap at once.
      textarea.addEventListener('input', () => {
        if (textarea.value.length > MESSAGE_MAX_CHARS) {
          textarea.value = textarea.value.slice(0, MESSAGE_MAX_CHARS);
          toast(`메시지가 잘렸어요 (최대 ${MESSAGE_MAX_CHARS.toLocaleString()}자)`, 'error');
        }
        textarea.style.height = 'auto';
        textarea.style.height = Math.min(textarea.scrollHeight, MAX_HEIGHT_PX) + 'px';
        const hasText = textarea.value.trim().length > 0;
        sendButton.disabled = frozen || !hasText;
        if (hasText) realtime.startTyping(convId);
        else realtime.stopTyping(convId);
        saveDraft(convId, textarea.value);
      });
      // No blur handler: the box blurs every time a redraw rebuilds it, and a
      // typing stop there would be wrong and prime the server's throttle.
      // Enter sends, unless an IME composition is still open.
      let composing = false;
      textarea.addEventListener('compositionstart', () => {
        composing = true;
      });
      textarea.addEventListener('compositionend', () => {
        composing = false;
      });
      textarea.addEventListener('keydown', (event) => {
        if (event.key === 'Enter' && !event.shiftKey && !composing && !event.isComposing) {
          event.preventDefault();
          sendTyped(textarea, convId);
        }
      });
      sendButton.disabled = true;

      const node = el('div', { class: 'panel-input-wrap' }, [
        replyBanner(convId, peerHandle),
        el('div', { class: 'panel-input' }, [textarea, fileButton, imageButton, voiceButton, sendButton]),
      ]);
      return { node, textarea };
    },

    // Quotes `message` in the next send of the conversation.
    startReply(convId, message) {
      const sender = message.senderDeviceId === state.me.deviceId ? state.me.handle : null;
      state.replyDrafts.set(convId, { id: message.id, snippet: snippetOf(message, 60), sender });
      store.notify('panels');
      requestAnimationFrame(() => textareaOf(convId)?.focus());
    },

    // Puts `text` in the conversation's composer for the user to send again;
    // with no composer on screen it is sent at once. Resolves to whether it
    // was put in the composer.
    async restoreText(convId, text) {
      const textarea = textareaOf(convId);
      if (!textarea) {
        if (store.conversation(convId)) await send.sendText(convId, text.trim());
        return false;
      }
      textarea.value = text;
      textarea.dispatchEvent(new Event('input'));
      textarea.focus();
      return true;
    },

    sendText: (convId, text) => send.sendText(convId, text.trim()),

    mount() {
      const inputOf = (event) => event.target.closest('.panel-input');
      document.addEventListener('dragover', (event) => {
        const target = inputOf(event);
        if (!target) return;
        event.preventDefault();
        target.classList.add('drag-over');
      });
      document.addEventListener('dragleave', (event) => inputOf(event)?.classList.remove('drag-over'));
      document.addEventListener('drop', (event) => {
        const target = inputOf(event);
        if (!target) return;
        event.preventDefault();
        target.classList.remove('drag-over');
        const convId = target.closest('.panel')?.dataset?.conv;
        const file = event.dataTransfer?.files?.[0];
        if (convId && file) offerImage(convId, file);
      });
    },
  };
}
