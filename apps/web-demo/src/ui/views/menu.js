// The top-right menu (#menu in index.html): the signed-in account with a
// button that copies the handle, then the actions; each names its action in
// data-action. A click anywhere else closes it.

import { t } from '../../../i18n/i18n.js';
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
        // The click may land on an item's icon or label.
        const action = event.target?.closest?.('[data-action]')?.dataset?.action;
        if (!action) return;
        menu.classList.add('hidden');
        actions[action]?.();
      });
    },
  };
}

export async function copyHandle(handle) {
  try {
    await navigator.clipboard.writeText('@' + handle);
    toast(t('menu.handleCopied'), 'good');
  } catch {
    toast(t('clipboard.failed'), 'error');
  }
}
