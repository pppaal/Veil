// The themed confirmation dialog (#confirm-dialog in index.html), the
// replacement for the native confirm(), and the focus trap the app's
// dialogs share.

import { $ } from './dom.js';

// Keeps Tab and Shift+Tab inside the dialog with id `dialogId`.
export function trapFocus(dialogId, event) {
  if (event.key !== 'Tab') return;
  const dialog = $(dialogId).querySelector('.dialog');
  if (!dialog) return;
  const focusable = [...dialog.querySelectorAll('input, button:not([disabled])')].filter((node) => !node.closest('.hidden'));
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
// with Esc, a click outside and Cancel all answering false. The title is a
// question and the OK button repeats its verb. `alternative`, when given,
// adds a middle button { label, onChoose }: it answers false and then runs
// onChoose, the safe way out of a destructive action.
export function createConfirm(dialogs) {
  return function confirm({ title, body = '', okLabel, cancelLabel, destructive = false, alternative = null } = {}) {
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
      const altBtn = $('confirm-alt');
      okBtn.textContent = okLabel;
      if (cancelLabel) cancelBtn.textContent = cancelLabel;
      altBtn.textContent = alternative?.label ?? '';
      altBtn.classList.toggle('hidden', !alternative);
      // A destructive action is a red text button, never a filled one.
      okBtn.classList.toggle('btn-primary', !destructive);
      okBtn.classList.toggle('btn-danger', destructive);

      const cleanup = (result) => {
        okBtn.removeEventListener('click', onOk);
        cancelBtn.removeEventListener('click', onCancel);
        altBtn.removeEventListener('click', onAlt);
        dialog.removeEventListener('click', onBackdrop);
        dialog.removeEventListener('keydown', onKey);
        dialogs.close('confirm-dialog');
        resolve(result);
      };
      const onOk = () => cleanup(true);
      const onCancel = () => cleanup(false);
      const onAlt = () => {
        cleanup(false);
        alternative?.onChoose?.();
      };
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
      altBtn.addEventListener('click', onAlt);
      dialog.addEventListener('click', onBackdrop);
      dialog.addEventListener('keydown', onKey);
      dialogs.open('confirm-dialog', 'confirm-cancel');
    });
  };
}
