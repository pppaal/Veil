// Transient notices at the top of the screen.

import { $, el } from './dom.js';

const FADE_MS = 220;

function fadeOutLater(node, afterMs) {
  setTimeout(() => {
    node.classList.add('leaving');
    setTimeout(() => node.remove(), FADE_MS);
  }, afterMs);
}

// kind: '' (neutral), 'good' or 'error'. A toast is text only, as
// Signal's, WhatsApp's and Telegram's are: the kind sets only how a screen
// reader hears it (an error is an alert) and how long it stays up.
export function toast(message, kind = '') {
  const node = el('div', { class: 'toast', role: kind === 'error' ? 'alert' : 'status' }, [
    el('span', { class: 'toast-message' }, [message]),
  ]);
  $('toast-root').appendChild(node);
  fadeOutLater(node, kind === 'error' ? 5000 : 2500);
}

// A notice with one action button, up for `durationMs`.
export function actionToast(message, actionLabel, onAction, durationMs) {
  const root = $('toast-root');
  if (!root) return;
  const node = el('div', { class: 'toast', role: 'status' }, [
    el('span', { class: 'toast-message' }, [message]),
    el(
      'button',
      {
        class: 'text-btn',
        onclick: () => {
          node.remove();
          onAction();
        },
      },
      [actionLabel],
    ),
  ]);
  root.appendChild(node);
  fadeOutLater(node, durationMs);
}
