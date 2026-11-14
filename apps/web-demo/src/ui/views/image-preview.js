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
    toast('JPG / PNG / WebP 만 지원해요', 'error');
    return false;
  }
  if (file.size > IMAGE_MAX_BYTES) {
    toast('이미지가 10MB 를 초과합니다', 'error');
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
  const send = el('button', { class: 'btn btn-primary' }, ['전송']);
  const backdrop = el('div', { class: 'image-zoom-backdrop', style: 'cursor: default;', role: 'dialog', 'aria-modal': 'true' }, [
    el('div', { style: 'background:#1c1d22;padding:16px;border-radius:14px;max-width:480px;width:90vw;display:flex;flex-direction:column;gap:12px' }, [
      el('div', { style: 'font-size:15px;font-weight:600' }, ['이미지 전송 확인']),
      el('div', { style: 'font-size:12px;opacity:0.7' }, [`${file.name || '이미지'} · ${(file.size / 1024).toFixed(0)} KB`]),
      el('img', { src: url, style: 'max-width:100%;max-height:50vh;border-radius:8px;object-fit:contain;background:#0b0c10' }),
      el('div', { style: 'display:flex;gap:8px;justify-content:flex-end' }, [
        el('button', { class: 'btn btn-ghost', onclick: close }, ['취소']),
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
