// Search inside a conversation: the bar under the panel header, the match
// counter, stepping through matches, and the marks on matching bubbles.
// Each conversation keeps its own search (open, query, position) while the
// session lasts.

import { highlightRuns, searchMatches, stepMatch } from '../../domain/search.js';
import { el } from '../dom.js';

const panelSelector = (convId) => `.panel[data-conv="${convId}"]`;
const searchInputOf = (convId) => document.querySelector(`${panelSelector(convId)} .panel-search input`);

export function createPanelSearch({ store }) {
  const { state } = store;

  function stateOf(convId) {
    if (!state.searches.has(convId)) state.searches.set(convId, { open: false, query: '', idx: 0 });
    return state.searches.get(convId);
  }

  const matchesOf = (convId, query) => searchMatches(store.messagesOf(convId), query);

  function open(convId) {
    stateOf(convId).open = true;
    store.notify('panels');
    requestAnimationFrame(() => searchInputOf(convId)?.focus());
  }

  function close(convId) {
    Object.assign(stateOf(convId), { open: false, query: '', idx: 0 });
    store.notify('panels');
  }

  function scrollToMatch(convId, messageId) {
    if (!messageId) return;
    document.querySelector(`${panelSelector(convId)} .msg-row[data-msg-id="${messageId}"]`)?.scrollIntoView({ behavior: 'smooth', block: 'center' });
  }

  return {
    open,

    // The search bar of a conversation, or null while its search is closed.
    render(convId) {
      const search = stateOf(convId);
      if (!search.open) return null;
      const query = search.query.trim();
      const matches = matchesOf(convId, query);
      const total = matches.length;
      if (search.idx >= total && total > 0) search.idx = total - 1;
      const step = (backwards) => {
        if (total === 0) return false;
        search.idx = stepMatch(search.idx, total, backwards);
        scrollToMatch(convId, matches[search.idx]?.id);
        store.notify('panels');
        return true;
      };

      const input = el('input', { type: 'text', placeholder: '대화에서 찾기…', 'aria-label': '메시지 검색' });
      input.value = search.query;
      input.addEventListener('input', () => {
        search.query = input.value;
        search.idx = 0;
        store.notify('panels');
        requestAnimationFrame(() => {
          const redrawn = searchInputOf(convId);
          if (!redrawn) return;
          redrawn.focus();
          redrawn.setSelectionRange(input.value.length, input.value.length);
        });
      });
      input.addEventListener('keydown', (event) => {
        if (event.key === 'Enter') {
          event.preventDefault();
          if (step(event.shiftKey)) requestAnimationFrame(() => searchInputOf(convId)?.focus());
        } else if (event.key === 'Escape') {
          close(convId);
        }
      });
      return el('div', { class: 'panel-search', role: 'search' }, [
        input,
        el('span', { class: 'count' }, [total > 0 ? `${search.idx + 1}/${total}` : (query ? '0/0' : '')]),
        el('button', { title: '이전 결과 (Shift+Enter)', onclick: () => step(true) }, ['↑']),
        el('button', { title: '다음 결과 (Enter)', onclick: () => step(false) }, ['↓']),
        el('button', { title: '닫기 (Esc)', onclick: () => close(convId) }, ['✕']),
      ]);
    },

    // Marks the matches in the bubbles just drawn: the current one's row is
    // outlined, and every occurrence in a matching bubble is wrapped in
    // <mark> (the bubble shows plain text while it matches).
    highlight() {
      for (const [convId, search] of state.searches) {
        const query = search.query.trim();
        if (!search.open || !query) continue;
        const panel = document.querySelector(panelSelector(convId));
        if (!panel) continue;
        matchesOf(convId, query).forEach((message, index) => {
          const row = panel.querySelector(`.msg-row[data-msg-id="${message.id}"]`);
          if (!row) return;
          if (index === search.idx) row.classList.add('search-active');
          row.querySelector('.msg-text')?.replaceChildren(
            ...highlightRuns(message.displayText, query).map((run) => (run.match ? el('mark', {}, [run.text]) : document.createTextNode(run.text))),
          );
        });
      }
    },

    mount() {
      // Ctrl/Cmd+F opens the active conversation's search, unless focus is
      // in another text field, where the browser's own find is left alone.
      document.addEventListener('keydown', (event) => {
        if (!(event.ctrlKey || event.metaKey) || (event.key !== 'f' && event.key !== 'F')) return;
        if (!state.activeConv) return;
        const target = event.target;
        const typing = target && (target.tagName === 'INPUT' || target.tagName === 'TEXTAREA' || target.isContentEditable);
        if (typing && !target.closest('.panel-search')) return;
        event.preventDefault();
        open(state.activeConv);
      });
    },
  };
}
