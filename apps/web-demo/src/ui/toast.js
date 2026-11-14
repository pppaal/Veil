// Transient notices at the top of the screen.

import { $, el } from './dom.js';

const FADE_MS = 220;

function fadeOutLater(node, afterMs) {
  setTimeout(() => {
    node.style.transition = 'opacity 0.2s ease';
    node.style.opacity = '0';
    setTimeout(() => node.remove(), FADE_MS);
  }, afterMs);
}

// kind: '' (neutral), 'good' or 'error'; errors stay up longer.
export function toast(message, kind = '') {
  const node = el('div', { class: `toast ${kind ? `toast-${kind}` : ''}` }, [message]);
  $('toast-root').appendChild(node);
  fadeOutLater(node, kind === 'error' ? 5000 : 2500);
}

// A notice with one action button, up for `durationMs`.
export function actionToast(message, actionLabel, onAction, durationMs) {
  const root = $('toast-root');
  if (!root) return;
  const node = el('div', { class: 'toast' }, [
    el('span', { style: 'flex:1' }, [message]),
    el(
      'button',
      {
        class: 'msg-action',
        style: 'background:rgba(255,255,255,0.12);padding:3px 10px;margin-left:10px;border-radius:6px;border:0;color:inherit;cursor:pointer',
        onclick: () => {
          node.remove();
          onAction();
        },
      },
      [actionLabel],
    ),
  ]);
  node.style.display = 'flex';
  node.style.alignItems = 'center';
  root.appendChild(node);
  fadeOutLater(node, durationMs);
}
