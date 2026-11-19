// The composer under a conversation: the text box with its in-memory
// draft, the reply or edit bar above it, the send button, the voice button,
// and the image and file pickers (also fed by dropping an image on it).

import { t } from '../../../i18n/i18n.js';
import { MESSAGE_MAX_CHARS } from '../../domain/composer-text.js';
import { snippetOf } from '../../domain/conversations.js';
import { shownHandle } from '../../domain/handles.js';
import { sanitizeFilename } from '../../domain/sanitize.js';
import { el, icon, iconButton } from '../dom.js';
import { toast } from '../toast.js';
import { checkImage, confirmImage, IMAGE_ACCEPT, isSendableImageType } from './image-preview.js';

const FILE_MAX_BYTES = 25 * 1024 * 1024;
// Five lines of the box (app.css .panel-input textarea), then it scrolls.
const MAX_HEIGHT_PX = 116;

const textareaOf = (convId) => document.querySelector(`.panel[data-conv="${convId}"] .panel-input textarea`);

// As tall as its text, up to five lines.
function fitHeight(textarea) {
  textarea.style.height = 'auto';
  textarea.style.height = Math.min(textarea.scrollHeight, MAX_HEIGHT_PX) + 'px';
}

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
      failureLabel: t('composer.imageNotSent'),
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
      failureLabel: t('composer.fileNotSent'),
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
        toast(t('composer.fileTooBig'), 'error');
        return;
      }
      sendFile(convId, file);
    });
  }

  function clearBox(textarea) {
    textarea.value = '';
    textarea.style.height = 'auto';
    textarea.dispatchEvent(new Event('input'));
  }

  // Ends the conversation's edit, sent or dropped, and gives back what was
  // being written (and the reply it quoted) when the edit began.
  function endEdit(convId) {
    const editing = state.editing.get(convId);
    if (!editing) return;
    state.editing.delete(convId);
    saveDraft(convId, editing.stashed.text);
    if (editing.stashed.reply) state.replyDrafts.set(convId, editing.stashed.reply);
  }

  // An edit in progress replaces the message's text; an unchanged or empty
  // one just ends the edit. Either way the draft comes back.
  function sendTyped(textarea, convId) {
    const editing = state.editing.get(convId);
    if (editing) {
      const text = textarea.value.trim();
      const message = store.findMessage(convId, editing.id);
      clearBox(textarea);
      endEdit(convId);
      store.notify('panels');
      if (message && text && text !== message.displayText) return send.edit(message, convId, text);
      return null;
    }
    const text = textarea.value.trim();
    const replyId = state.replyDrafts.get(convId)?.id ?? null;
    return send.sendText(convId, text, {
      onSealed: () => {
        // An edit begun while this was sealing set aside the text being sent
        // (and the reply it quotes) to give back when the edit ends. It is
        // sent now: nothing of it comes back, and the box keeps the edit.
        const editing = state.editing.get(convId);
        if (!editing) {
          clearBox(textarea);
          return;
        }
        if (editing.stashed.text.trim() === text) editing.stashed.text = '';
        if (replyId && editing.stashed.reply?.id === replyId) editing.stashed.reply = null;
      },
    });
  }

  // The bar above the box while a reply or an edit is under way, with its
  // cancel button.
  function bar(meta, snippet, cancelLabel, onCancel, className = '') {
    return el('div', { class: `reply-banner ${className}`.trim() }, [
      el('div', { class: 'reply-banner-body' }, [
        el('div', { class: 'reply-banner-meta' }, [meta]),
        el('div', { class: 'reply-banner-snippet' }, [snippet]),
      ]),
      iconButton('close', cancelLabel, { class: 'icon-btn reply-banner-close', onclick: onCancel }),
    ]);
  }

  function replyBanner(convId, peerHandle) {
    const editing = state.editing.get(convId);
    if (editing) {
      return bar(t('msg.editing'), editing.snippet, t('msg.cancelEdit'), () => {
        endEdit(convId);
        store.notify('panels');
      }, 'edit-banner');
    }
    const draft = state.replyDrafts.get(convId);
    if (!draft) return null;
    return bar(t('msg.replyTo', { handle: shownHandle(draft.sender ?? peerHandle) }), draft.snippet, t('msg.cancelReply'), () => {
      state.replyDrafts.delete(convId);
      store.notify('panels');
    });
  }

  function attachButton(className, iconName, label, title, onClick) {
    return iconButton(iconName, label, { class: `icon-btn ${className}`, title, onclick: onClick });
  }

  return {
    // The composer of a conversation; a frozen one takes no text, and its
    // placeholder says why. Returns { node, textarea }.
    render(convId, { frozen, placeholder, peerHandle }) {
      const textarea = el('textarea', { placeholder, rows: '1', 'aria-label': t('msg.input.placeholder'), maxlength: String(MESSAGE_MAX_CHARS) });
      textarea.disabled = frozen;
      const draft = state.drafts.get(convId);
      if (draft) textarea.value = draft.slice(0, MESSAGE_MAX_CHARS);
      // Shown only while there is a draft to send (app.css hides it disabled).
      const sendButton = el('button', { class: 'send-btn', type: 'button', 'aria-label': t('composer.send'), title: t('composer.send'), onclick: () => sendTyped(textarea, convId) }, [
        el('span', { class: 'send-circle' }, [icon('arrow-up')]),
      ]);
      const voiceButton = voice.button(convId);
      voiceButton.disabled = frozen;
      const fileButton = attachButton('file-btn image-btn', 'paperclip', t('composer.attachFile'), t('composer.attachFile'), () => pickAnyFile(convId));
      const imageButton = attachButton('image-btn', 'image', t('composer.attachImage'), t('composer.attachImage'), () => pickFile(IMAGE_ACCEPT, (file) => offerImage(convId, file)));

      // On every input: grow, send typing, keep the draft. maxlength holds
      // typing back, but a paste can still land over the cap at once.
      textarea.addEventListener('input', () => {
        if (textarea.value.length > MESSAGE_MAX_CHARS) {
          textarea.value = textarea.value.slice(0, MESSAGE_MAX_CHARS);
          toast(t('composer.cut', { max: MESSAGE_MAX_CHARS.toLocaleString() }), 'error');
        }
        fitHeight(textarea);
        const hasText = textarea.value.trim().length > 0;
        sendButton.disabled = frozen || !hasText;
        // Editing an old message is not typing a new one.
        if (hasText && !state.editing.has(convId)) realtime.startTyping(convId);
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
        } else if (event.key === 'Escape' && state.editing.has(convId)) {
          event.preventDefault();
          endEdit(convId);
          store.notify('panels');
        }
      });
      // A draft carried across a redraw keeps its send button.
      sendButton.disabled = frozen || textarea.value.trim().length === 0;
      // ...and its height, once the box is on the page.
      if (textarea.value) requestAnimationFrame(() => fitHeight(textarea));

      const node = el('div', { class: 'panel-input-wrap' }, [
        replyBanner(convId, peerHandle),
        el('div', { class: 'panel-input' }, [textarea, fileButton, imageButton, voiceButton, sendButton]),
      ]);
      return { node, textarea };
    },

    // Quotes `message` in the next send of the conversation; an edit under
    // way is dropped first.
    startReply(convId, message) {
      const sender = message.senderDeviceId === state.me.deviceId ? state.me.handle : null;
      endEdit(convId);
      state.replyDrafts.set(convId, { id: message.id, snippet: snippetOf(message, 60), sender });
      store.notify('panels');
      requestAnimationFrame(() => textareaOf(convId)?.focus());
    },

    // Puts our own `message` in the box to edit; Enter saves the edit, Esc
    // or the bar's close button drops it. What was being written waits
    // aside until then (editing another message meanwhile keeps it there).
    startEdit(convId, message) {
      const stashed = state.editing.get(convId)?.stashed ?? {
        text: state.drafts.get(convId) ?? '',
        reply: state.replyDrafts.get(convId) ?? null,
      };
      state.replyDrafts.delete(convId);
      state.editing.set(convId, { id: message.id, snippet: snippetOf(message, 60), stashed });
      state.drafts.set(convId, message.displayText);
      store.notify('panels');
      requestAnimationFrame(() => {
        const textarea = textareaOf(convId);
        if (!textarea) return;
        textarea.focus();
        textarea.setSelectionRange(textarea.value.length, textarea.value.length);
      });
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
