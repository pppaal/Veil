// The conversation list in the sidebar, filtered by the search box, with
// the imported Kakao archives below it.

import { t } from '../../../i18n/i18n.js';
import { matchesSearch, previewMessage, shownPeer } from '../../domain/conversations.js';
import { previewLabel } from '../../domain/ingest.js';
import { $, avatarFor, convSkeletons, el } from '../dom.js';
import { relativeTime } from '../time.js';

// navigation: src/ui/views/tabs.js; archiveRows(): the Kakao archive rows
// (src/ui/views/kakao-import.js).
export function createSidebar({ store, stack, navigation, archiveRows }) {
  const { state } = store;

  function conversationRow(conv, now) {
    const peer = shownPeer(conv, state.me.handle);
    const isActive = store.isOnScreen(conv.id);
    const last = previewMessage(conv, store.messagesOf(conv.id), now);
    const preview = last ? previewLabel(last, now) : '아직 메시지 없음';
    const time = last?.serverReceivedAt ? relativeTime(last.serverReceivedAt) : '';
    const keyChanged = peer && stack.trust.pendingChange(peer.userId);
    const directPeer = stack.peerOf(conv.id);
    const otherAccount = directPeer && stack.bindings.handleConflict(conv.id, directPeer);
    const avatar = avatarFor(peer?.handle ?? '?', 'md');
    avatar.appendChild(el('span', { class: 'presence-dot' }));
    if (peer && state.online.has(peer.userId)) avatar.classList.add('online');
    let className = 'conv-item';
    if (isActive) className += ' active';
    if (state.muted.has(conv.id)) className += ' muted';
    return el('button', { class: className, dataset: { convId: conv.id }, onclick: () => navigation.open(conv.id) }, [
      avatar,
      el('div', { class: 'conv-meta' }, [
        el('div', { class: 'conv-row1' }, [
          el('span', { class: 'conv-name' }, ['@' + (peer?.handle ?? '?')]),
          time ? el('span', { class: 'conv-time' }, [time]) : null,
        ]),
        el('div', { class: 'conv-preview' }, [otherAccount ? t('accountConflict.sidebar') : keyChanged ? t('keyChange.sidebar') : preview]),
      ]),
    ]);
  }

  function render() {
    const list = $('conv-list');
    const query = ($('search-input').value || '').trim().toLowerCase();
    const filtered = state.conversations.filter((conv) => matchesSearch(conv, query));
    if (filtered.length === 0) {
      // Until the first /conversations response lands, shimmering rows stand
      // in: "no conversations" would be untrue for that moment.
      if (!state.conversationsLoaded && !query) {
        list.replaceChildren(...convSkeletons(4));
        return;
      }
      list.replaceChildren(
        el('div', { class: 'conv-empty' }, [query ? `"${query}" 검색 결과 없음` : '대화 없음. + 새 대화 버튼으로 시작하세요.']),
        ...archiveRows(),
      );
      return;
    }
    const now = Date.now();
    list.replaceChildren(...filtered.map((conv) => conversationRow(conv, now)), ...archiveRows());
  }

  return {
    render,
    mount() {
      $('search-input').addEventListener('input', render);
    },
  };
}
