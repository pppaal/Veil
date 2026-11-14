// The themed confirmation dialog (#confirm-dialog in index.html), the
// replacement for the native confirm(), and the focus trap the app's
// dialogs share.

import { $ } from './dom.js';

// Keeps Tab and Shift+Tab inside the dialog with id `dialogId`.
export function trapFocus(dialogId, event) {
  if (event.key !== 'Tab') return;
  const dialog = $(dialogId).querySelector('.dialog');
  if (!dialog) return;
  const focusable = dialog.querySelectorAll('input, button:not([disabled])');
  if (focusable.length === 0) return;
  const first = focusable[0];
  const last = focusable[focusable.length - 1];
  if (event.shiftKey && document.activeElement === first) {
    event.preventDefault();
    last.focus();
  } else if (!event.shiftKey && document.activeElement === last) {
    event.preventDefault();
    first.focus();
  }
}

// dialogs: src/ui/dialogs.js. Returns confirm(options) -> Promise<boolean>,
// with Esc, a click outside and Cancel all answering false.
export function createConfirm(dialogs) {
  return function confirm({ title = '확인', body = '', okLabel = '확인', cancelLabel = '취소', destructive = false } = {}) {
    return new Promise((resolve) => {
      const dialog = $('confirm-dialog');
      if (!dialog) {
        resolve(false);
        return;
      }
      $('confirm-title').textContent = title;
      $('confirm-body').textContent = body;
      const okBtn = $('confirm-ok');
      const cancelBtn = $('confirm-cancel');
      okBtn.textContent = okLabel;
      cancelBtn.textContent = cancelLabel;
      okBtn.classList.toggle('btn-primary', !destructive);
      okBtn.classList.toggle('btn-secondary', destructive);
      okBtn.style.background = destructive ? 'var(--bad)' : '';
      okBtn.style.borderColor = destructive ? 'var(--bad)' : '';

      const cleanup = (result) => {
        okBtn.removeEventListener('click', onOk);
        cancelBtn.removeEventListener('click', onCancel);
        dialog.removeEventListener('click', onBackdrop);
        dialog.removeEventListener('keydown', onKey);
        okBtn.style.background = '';
        okBtn.style.borderColor = '';
        dialogs.close('confirm-dialog');
        resolve(result);
      };
      const onOk = () => cleanup(true);
      const onCancel = () => cleanup(false);
      const onBackdrop = (event) => {
        if (event.target === dialog) cleanup(false);
      };
      const onKey = (event) => {
        if (event.key === 'Escape') {
          event.preventDefault();
          cleanup(false);
        } else {
          trapFocus('confirm-dialog', event);
        }
      };
      okBtn.addEventListener('click', onOk);
      cancelBtn.addEventListener('click', onCancel);
      dialog.addEventListener('click', onBackdrop);
      dialog.addEventListener('keydown', onKey);
      dialogs.open('confirm-dialog', 'confirm-cancel');
    });
  };
}
