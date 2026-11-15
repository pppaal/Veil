// Transient notices at the top of the screen.

import { $, el, icon } from './dom.js';

const FADE_MS = 220;
// The kind of a toast shows only as its leading icon.
const KIND_ICONS = { good: 'check', error: 'warning' };

function fadeOutLater(node, afterMs) {
  setTimeout(() => {
    node.classList.add('leaving');
    setTimeout(() => node.remove(), FADE_MS);
  }, afterMs);
}

// kind: '' (neutral), 'good' or 'error'; errors stay up longer.
export function toast(message, kind = '') {
  const node = el('div', { class: `toast ${kind ? `toast-${kind}` : ''}`, role: kind === 'error' ? 'alert' : 'status' }, [
    KIND_ICONS[kind] ? icon(KIND_ICONS[kind], 'toast-icon') : null,
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
