// Forwarding a text to another conversation: sent there as a fresh message,
// with no quote of the original and no link to it.

import { isTextKind } from '../../domain/ingest.js';
import { avatarFor, el, handleLine } from '../dom.js';
import { toast } from '../toast.js';

// composer: src/ui/views/composer.js.
export function createForwardDialog({ store, composer }) {
  const { state } = store;

  return {
    open(message) {
      if (!isTextKind(message.kind) || message.displayText === '') {
        toast('전달할 내용이 없어요', 'error');
        return;
      }
      const others = state.conversations.filter((conv) => conv.id !== message.conversationId);
      if (others.length === 0) {
        toast('전달할 다른 대화가 없어요');
        return;
      }
      const list = el('div', { class: 'forward-list' });
      const cancelButton = el('button', { class: 'btn btn-ghost', id: 'fwd-cancel' }, ['취소']);
      const confirmButton = el('button', { class: 'btn btn-primary', id: 'fwd-confirm', disabled: 'disabled' }, ['전달']);
      const backdrop = el('div', { class: 'dialog-backdrop', role: 'presentation' }, [
        el('div', { class: 'dialog', role: 'dialog', 'aria-modal': 'true', 'aria-labelledby': 'fwd-title', style: 'width:380px;max-width:92vw' }, [
          el('div', { class: 'dialog-title', id: 'fwd-title' }, ['메시지 전달']),
          el('div', { class: 'dialog-sub' }, ['전달할 대화를 고르세요. 원본 인용 없이 새 메시지로 보내져요.']),
          list,
          el('div', { class: 'dialog-actions' }, [cancelButton, confirmButton]),
        ]),
      ]);
      document.body.appendChild(backdrop);
      let selected = null;
      for (const conv of others) {
        const peer = conv.members?.find((member) => member.userId !== state.me?.userId);
        const row = el('div', { class: 'forward-list-item', dataset: { convId: conv.id } }, [
          avatarFor(peer?.handle ?? '?', 'sm'),
          el('div', { style: 'flex:1' }, [handleLine(peer?.handle)]),
        ]);
        row.addEventListener('click', () => {
          list.querySelectorAll('.forward-list-item').forEach((other) => other.classList.remove('selected'));
          row.classList.add('selected');
          selected = conv.id;
          confirmButton.disabled = false;
        });
        list.appendChild(row);
      }
      const close = () => backdrop.remove();
      cancelButton.addEventListener('click', close);
      backdrop.addEventListener('click', (event) => {
        if (event.target === backdrop) close();
      });
      confirmButton.addEventListener('click', async () => {
        if (!selected) return;
        close();
        await composer.sendText(selected, message.displayText);
        toast('전달했습니다', 'good');
      });
    },
  };
}
