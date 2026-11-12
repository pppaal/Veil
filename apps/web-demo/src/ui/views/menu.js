// The top-right menu (#menu in index.html): each item names its action in
// data-action. A click anywhere else closes it.

import { $ } from '../dom.js';
import { toast } from '../toast.js';

// actions: { [action]: () => void } for the items' data-action values.
export function createMenu({ actions }) {
  return {
    mount() {
      const menu = $('menu');
      $('menu-btn').addEventListener('click', (event) => {
        event.stopPropagation();
        menu.classList.toggle('hidden');
      });
      document.addEventListener('click', () => menu.classList.add('hidden'));
      menu.addEventListener('click', (event) => {
        event.stopPropagation();
        const action = event.target?.dataset?.action;
        if (!action) return;
        menu.classList.add('hidden');
        actions[action]?.();
      });
    },
  };
}

// The handle and connection-status items.
export async function copyHandle(handle) {
  try {
    await navigator.clipboard.writeText('@' + handle);
    toast('핸들을 복사했습니다', 'good');
  } catch {
    toast('클립보드 접근 실패', 'error');
  }
}

export function showConnectionStatus(connected, pollMs) {
  toast('연결: ' + (connected ? '실시간 (WebSocket)' : '폴링 (' + pollMs / 1000 + '초)'), 'good');
}
