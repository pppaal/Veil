// The new direct chat dialog (#new-chat-dialog in index.html): a peer's
// handle in, the conversation open in a tab.

import { normalizeHandle } from '../../domain/composer-text.js';
import { trapFocus } from '../confirm.js';
import { $ } from '../dom.js';

const DIALOG_ID = 'new-chat-dialog';

// history: src/app/services/history-sync.js; tabs: src/ui/views/tabs.js;
// dialogs: src/ui/dialogs.js.
export function createNewChatDialog({ store, stack, history, tabs, dialogs }) {
  async function start() {
    const peer = normalizeHandle($('new-peer-input').value);
    if (!peer) {
      $('new-peer-error').textContent = '핸들을 입력하세요';
      return;
    }
    if (peer === store.state.me.handle) {
      $('new-peer-error').textContent = '자기 자신과는 대화할 수 없어요';
      return;
    }
    $('new-confirm').disabled = true;
    try {
      const created = await stack.authedApi('/conversations/direct', { method: 'POST', body: { peerHandle: peer } });
      dialogs.close(DIALOG_ID);
      await history.loadConversations();
      await tabs.open(created.conversation.id);
    } catch (error) {
      $('new-peer-error').textContent = error.message;
    } finally {
      $('new-confirm').disabled = false;
    }
  }

  return {
    mount() {
      $('new-chat-btn').addEventListener('click', () => {
        $('new-peer-input').value = '';
        $('new-peer-error').textContent = '';
        dialogs.open(DIALOG_ID, 'new-peer-input');
      });
      $('new-cancel').addEventListener('click', () => dialogs.close(DIALOG_ID));
      $('new-confirm').addEventListener('click', start);
      $('new-peer-input').addEventListener('keydown', (event) => {
        if (event.key === 'Enter' && !event.isComposing) $('new-confirm').click();
      });
      const dialog = $(DIALOG_ID);
      dialog.addEventListener('click', (event) => {
        if (event.target.id === DIALOG_ID) dialogs.close(DIALOG_ID);
      });
      dialog.addEventListener('keydown', (event) => {
        if (event.key === 'Escape') {
          event.preventDefault();
          dialogs.close(DIALOG_ID);
        } else {
          trapFocus(DIALOG_ID, event);
        }
      });
    },
  };
}
