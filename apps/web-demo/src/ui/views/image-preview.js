// Images on screen outside a bubble: the zoomed view, and the confirmation
// shown before a picked or dropped image is encrypted and uploaded, so a
// wrong drop or a slip of the finger does not send it.

import { el } from '../dom.js';
import { toast } from '../toast.js';

export const IMAGE_MAX_BYTES = 10 * 1024 * 1024;
const IMAGE_TYPES = new Set(['image/jpeg', 'image/png', 'image/webp']);
export const IMAGE_ACCEPT = 'image/jpeg,image/png,image/webp';

export const isSendableImageType = (type) => IMAGE_TYPES.has(type);

export function openImageZoom(url) {
  const backdrop = el('div', { class: 'image-zoom-backdrop' }, [el('img', { src: url })]);
  backdrop.addEventListener('click', () => backdrop.remove());
  document.body.appendChild(backdrop);
}

// Whether `file` may be sent as an image; says why not when it may not.
export function checkImage(file) {
  if (!isSendableImageType(file.type)) {
    toast('Only JPG, PNG and WebP images can be sent', 'error');
    return false;
  }
  if (file.size > IMAGE_MAX_BYTES) {
    toast('The image is larger than 10 MB', 'error');
    return false;
  }
  return true;
}

// Asks before sending `file`; onSend() once the user confirms.
export function confirmImage(file, onSend) {
  if (!checkImage(file)) return;
  const url = URL.createObjectURL(file);
  const close = () => {
    URL.revokeObjectURL(url);
    backdrop.remove();
  };
  const onKey = (event) => {
    if (event.key === 'Escape') {
      close();
      document.removeEventListener('keydown', onKey);
    }
  };
  const send = el('button', { class: 'btn btn-primary' }, ['Send']);
  const backdrop = el('div', { class: 'dialog-backdrop image-confirm', role: 'dialog', 'aria-modal': 'true', 'aria-labelledby': 'image-confirm-title' }, [
    el('div', { class: 'dialog dialog-wide' }, [
      el('div', { class: 'dialog-title', id: 'image-confirm-title' }, ['Send this image?']),
      el('div', { class: 'dialog-sub' }, [`${file.name || 'Image'}, ${(file.size / 1024).toFixed(0)} KB`]),
      el('img', { class: 'image-confirm-preview', src: url, alt: '' }),
      el('div', { class: 'dialog-actions' }, [
        el('button', { class: 'btn btn-ghost', onclick: close }, ['Cancel']),
        send,
      ]),
    ]),
  ]);
  backdrop.addEventListener('click', (event) => {
    if (event.target === backdrop) close();
  });
  send.addEventListener('click', () => {
    close();
    onSend();
  });
  document.addEventListener('keydown', onKey);
  document.body.appendChild(backdrop);
  send.focus();
}
