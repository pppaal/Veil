// The new direct chat dialog (#new-chat-dialog in index.html): a peer's
// handle in, the conversation open in a tab.

import { t } from '../../../i18n/i18n.js';
import { normalizeHandle } from '../../domain/composer-text.js';
import { ApiError } from '../../platform/api-client.js';
import { trapFocus } from '../confirm.js';
import { $ } from '../dom.js';

const DIALOG_ID = 'new-chat-dialog';

// The server answers an unknown handle with a 404; anything else is a
// failure to reach it or to start the chat, and its wording stays off the
// screen.
const isNotFound = (error) => error instanceof ApiError && (error.status === 404 || error.code === 'handle_not_found');

// history: src/app/services/history-sync.js; tabs: src/ui/views/tabs.js;
// dialogs: src/ui/dialogs.js.
export function createNewChatDialog({ store, stack, history, tabs, dialogs }) {
  const showError = (text) => {
    $('new-peer-error').textContent = text;
  };

  async function start() {
    // The field shows a fixed "@"; a pasted "@sam" means sam.
    const peer = normalizeHandle($('new-peer-input').value).replace(/^@+/, '');
    if (!peer) {
      showError(t('auth.form.handle.missing'));
      return;
    }
    if (peer === store.state.me.handle) {
      showError(t('newChat.self'));
      return;
    }
    $('new-confirm').disabled = true;
    try {
      const created = await stack.authedApi('/conversations/direct', { method: 'POST', body: { peerHandle: peer } });
      dialogs.close(DIALOG_ID);
      await history.loadConversations();
      await tabs.open(created.conversation.id);
    } catch (error) {
      showError(isNotFound(error) ? t('newChat.notFound', { handle: peer }) : t('newChat.failed'));
    } finally {
      $('new-confirm').disabled = false;
    }
  }

  return {
    mount() {
      $('new-chat-btn').addEventListener('click', () => {
        $('new-peer-input').value = '';
        showError('');
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
