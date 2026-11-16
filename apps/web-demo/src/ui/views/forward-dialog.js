// Forwarding a text to another conversation: sent there as a fresh message,
// with no quote of the original and no link to it. The dialog is a search
// field and the chats to pick from.

import { t } from '../../../i18n/i18n.js';
import { shownHandle } from '../../domain/handles.js';
import { isTextKind } from '../../domain/ingest.js';
import { avatarFor, el, handleLine, icon } from '../dom.js';
import { toast } from '../toast.js';

// stack: src/app/messaging-stack.js (shownPeer names a conversation);
// composer: src/ui/views/composer.js.
export function createForwardDialog({ store, stack, composer }) {
  const { state } = store;

  return {
    open(message) {
      if (!isTextKind(message.kind) || message.displayText === '') {
        toast(t('forward.nothing'), 'error');
        return;
      }
      const others = state.conversations.filter((conv) => conv.id !== message.conversationId);
      if (others.length === 0) {
        toast(t('forward.empty'));
        return;
      }
      const search = el('input', { type: 'text', class: 'forward-search', placeholder: t('search.placeholder'), 'aria-label': t('search.placeholder'), autocomplete: 'off' });
      const list = el('div', { class: 'forward-list' });
      const cancelButton = el('button', { class: 'btn btn-ghost', id: 'fwd-cancel' }, [t('common.cancel')]);
      const confirmButton = el('button', { class: 'btn btn-primary', id: 'fwd-confirm', disabled: 'disabled' }, [t('forward.confirm')]);
      const backdrop = el('div', { class: 'dialog-backdrop', role: 'presentation' }, [
        el('div', { class: 'dialog', role: 'dialog', 'aria-modal': 'true', 'aria-labelledby': 'fwd-title' }, [
          el('div', { class: 'dialog-title', id: 'fwd-title' }, [t('forward.title')]),
          search,
          list,
          el('div', { class: 'dialog-actions' }, [cancelButton, confirmButton]),
        ]),
      ]);
      document.body.appendChild(backdrop);
      let selected = null;
      const rows = others.map((conv) => {
        const peer = stack.shownPeer(conv);
        const row = el('div', { class: 'forward-list-item', dataset: { convId: conv.id, handle: shownHandle(peer?.handle) } }, [
          avatarFor(peer?.handle ?? '?', 'sm'),
          handleLine(peer?.handle),
          icon('check', 'check'),
        ]);
        row.addEventListener('click', () => {
          list.querySelectorAll('.forward-list-item').forEach((other) => other.classList.remove('selected'));
          row.classList.add('selected');
          selected = conv.id;
          confirmButton.disabled = false;
        });
        list.appendChild(row);
        return row;
      });
      search.addEventListener('input', () => {
        const query = search.value.trim().toLowerCase().replace(/^@/, '');
        for (const row of rows) row.hidden = Boolean(query) && !row.dataset.handle.toLowerCase().includes(query);
      });
      const close = () => backdrop.remove();
      cancelButton.addEventListener('click', close);
      backdrop.addEventListener('click', (event) => {
        if (event.target === backdrop) close();
      });
      confirmButton.addEventListener('click', async () => {
        if (!selected) return;
        close();
        await composer.sendText(selected, message.displayText);
        toast(t('forward.done'), 'good');
      });
      search.focus();
    },
  };
}
