// The conversation list in the sidebar, filtered by the search box, with
// the imported Kakao archives below it.

import { t } from '../../../i18n/i18n.js';
import { expiryNow } from '../../core/expiry.js';
import { matchesSearch, previewMessage } from '../../domain/conversations.js';
import { shownHandle } from '../../domain/handles.js';
import { previewLabel } from '../../domain/ingest.js';
import { $, avatarFor, el, icon } from '../dom.js';
import { relativeTime } from '../time.js';
import { holdTextKey } from './key-change-banner.js';

// navigation: src/ui/views/tabs.js; archiveRows(): the Kakao archive rows
// (src/ui/views/kakao-import.js).
export function createSidebar({ store, stack, navigation, archiveRows }) {
  const { state } = store;

  function conversationRow(conv, now) {
    // Named after the peer its crypto is about (src/domain/conversations.js
    // shownPeer), never after a member picked by handle.
    const peer = stack.shownPeer(conv);
    const isActive = store.isOnScreen(conv.id);
    const last = previewMessage(conv, store.messagesOf(conv.id), now);
    const preview = last ? previewLabel(last, now) : t('conv.noMessages');
    const time = last?.serverReceivedAt ? relativeTime(last.serverReceivedAt) : '';
    const keyChanged = peer && stack.trust.pendingChange(peer.userId);
    const directPeer = stack.peerOf(conv.id);
    // Held for the handle it is listed under (src/domain/peer-bindings.js
    // hold): the row says so instead of previewing what it holds.
    const hold = directPeer ? stack.bindings.hold(conv.id, directPeer) : null;
    const muted = store.isMuted(conv.id);
    let className = 'conv-item';
    if (isActive) className += ' active';
    if (muted) className += ' muted';
    return el('button', { class: className, dataset: { convId: conv.id }, onclick: () => navigation.open(conv.id) }, [
      avatarFor(peer?.handle ?? '?', 'md'),
      el('div', { class: 'conv-meta' }, [
        el('div', { class: 'conv-row1' }, [
          el('span', { class: 'conv-name' }, ['@' + shownHandle(peer?.handle)]),
          muted ? icon('bell-off', 'conv-muted') : null,
          time ? el('span', { class: 'conv-time' }, [time]) : null,
        ]),
        el('div', { class: 'conv-preview' }, [hold ? t(holdTextKey(hold, 'sidebar')) : keyChanged ? t('keyChange.sidebar') : preview]),
      ]),
    ]);
  }

  function render() {
    const list = $('conv-list');
    const query = ($('search-input').value || '').trim().toLowerCase();
    const filtered = state.conversations.filter((conv) => matchesSearch(conv, query));
    if (filtered.length === 0) {
      // Until the first /conversations response lands the list stays empty:
      // "no conversations" would be untrue for that moment.
      if (!state.conversationsLoaded && !query) {
        list.replaceChildren();
        return;
      }
      // No chats: the title and the one thing to do. No results: one line.
      const empty = query
        ? el('div', { class: 'conv-empty' }, [t('conv.noResults', { query })])
        : el('div', { class: 'conv-empty' }, [
          el('div', { class: 'conv-empty-title' }, [t('conv.empty')]),
          el('button', { class: 'btn btn-primary btn-compact', onclick: () => $('new-chat-btn').click() }, [t('newChat.title')]),
        ]);
      list.replaceChildren(empty, ...archiveRows());
      return;
    }
    const now = expiryNow();
    list.replaceChildren(...filtered.map((conv) => conversationRow(conv, now)), ...archiveRows());
  }

  return {
    render,
    mount() {
      $('search-input').addEventListener('input', render);
    },
  };
}
