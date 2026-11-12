// Which conversations are open and shown: the tab strip, the split view
// with a second panel, and the narrow layout's switch between the list and
// a chat.

import { shownHandle } from '../../domain/handles.js';
import { $, el } from '../dom.js';
import { toast } from '../toast.js';

const NARROW_LAYOUT = '(max-width: 720px)';

// stack: src/app/messaging-stack.js (shownPeer names a tab); history:
// src/app/services/history-sync.js.
export function createTabs({ store, stack, history }) {
  const { state } = store;

  // In split view the conversation shown so far moves to the right panel.
  function activate(convId) {
    if (state.splitView && state.activeConv && state.activeConv !== convId) state.secondaryConv = state.activeConv;
    state.activeConv = convId;
    if (state.secondaryConv === convId) state.secondaryConv = null;
    // Only an explicit open or switch focuses the composer, never a redraw
    // a push caused: that would pop the mobile keyboard back up.
    state.focusClaims.add(convId);
  }

  function close(convId) {
    const index = state.openTabs.indexOf(convId);
    if (index === -1) return;
    state.openTabs.splice(index, 1);
    if (state.secondaryConv === convId) state.secondaryConv = null;
    if (state.activeConv === convId) {
      state.activeConv = state.openTabs[Math.min(index, state.openTabs.length - 1)] || null;
      if (state.activeConv === state.secondaryConv) state.secondaryConv = null;
    }
    if (state.splitView && !state.secondaryConv && state.activeConv) {
      state.secondaryConv = state.openTabs.find((id) => id !== state.activeConv) || null;
    }
    if (!state.activeConv) $('app').classList.remove('viewing-chat');
    state.scrollTops.delete(convId);
    store.notify('sidebar', 'tabs', 'panels');
  }

  function toggleSplit() {
    if (window.matchMedia && window.matchMedia(NARROW_LAYOUT).matches) {
      toast('분할 보기는 데스크탑에서만 사용할 수 있어요', 'error');
      return;
    }
    state.splitView = !state.splitView;
    $('split-btn').classList.toggle('active', state.splitView);
    if (state.splitView) {
      state.secondaryConv = state.openTabs.find((id) => id !== state.activeConv) || null;
      if (!state.secondaryConv) toast('탭을 두 개 이상 열어주세요', 'good');
    } else {
      state.secondaryConv = null;
    }
    store.notify('tabs', 'panels');
  }

  function tab(convId) {
    const conv = store.conversation(convId);
    const peer = conv ? stack.shownPeer(conv) : null;
    let className = 'tab';
    if (state.activeConv === convId) className += ' active';
    if (state.secondaryConv === convId) className += ' secondary';
    const closeButton = el('span', {
      class: 'tab-close',
      'aria-label': '탭 닫기',
      role: 'button',
      onclick: (event) => {
        event.stopPropagation();
        close(convId);
      },
    }, ['×']);
    return el('button', {
      class: className,
      onclick: () => {
        activate(convId);
        store.notify('sidebar', 'tabs', 'panels');
      },
      title: peer?.handle ? '@' + shownHandle(peer.handle) : '대화',
    }, [el('span', {}, ['@' + shownHandle(peer?.handle)]), closeButton]);
  }

  return {
    // Opens a conversation in a tab and the main panel, and fetches what
    // arrived since it was last shown.
    async open(convId) {
      if (!state.openTabs.includes(convId)) state.openTabs.push(convId);
      activate(convId);
      $('app').classList.add('viewing-chat');
      store.notify('sidebar', 'tabs', 'panels');
      await history.refreshMessages(convId);
    },

    render() {
      $('tab-strip').replaceChildren(...state.openTabs.map(tab));
    },

    mount() {
      $('split-btn').addEventListener('click', toggleSplit);
      $('back-to-list').addEventListener('click', () => {
        state.activeConv = null;
        $('app').classList.remove('viewing-chat');
        store.notify('sidebar', 'panels');
      });
    },
  };
}
