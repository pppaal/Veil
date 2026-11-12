// @mention autocomplete in the composer: while the caret follows "@prefix"
// (src/domain/composer-text.js mentionAt), a popover lists the members of
// the active conversation whose handle starts with it. The listeners sit on
// the document, so every redrawn composer has them.

import { completeMention, mentionAt, mentionCandidates } from '../../domain/composer-text.js';
import { avatarFor, el, handleLine } from '../dom.js';

const mentionOf = (textarea) => mentionAt(textarea.value, textarea.selectionStart ?? textarea.value.length);

export function createMentions({ store }) {
  const { state } = store;
  let popover = null;

  function close() {
    if (!popover) return;
    popover.remove();
    popover = null;
  }

  function complete(textarea, mention, handle) {
    const caret = textarea.selectionStart ?? textarea.value.length;
    const next = completeMention(textarea.value, caret, mention, handle);
    textarea.value = next.value;
    textarea.setSelectionRange(next.caret, next.caret);
    textarea.dispatchEvent(new Event('input'));
    close();
    textarea.focus();
  }

  function show(textarea, mention) {
    close();
    const members = store.conversation(state.activeConv)?.members ?? [];
    const candidates = mentionCandidates(members, state.me?.userId, mention.prefix);
    const node = el('div', { class: 'mention-pop', role: 'listbox' });
    if (candidates.length === 0) {
      node.appendChild(el('div', { class: 'mention-pop-empty' }, ['일치하는 핸들 없음']));
    }
    candidates.forEach((member, index) => {
      const item = el('div', {
        class: 'mention-pop-item' + (index === 0 ? ' active' : ''),
        dataset: { handle: member.handle, userId: member.userId },
        role: 'option',
      }, [avatarFor(member.handle, 'sm'), el('div', {}, [handleLine(member.handle)])]);
      item.addEventListener('mousedown', (event) => {
        event.preventDefault();
        complete(textarea, mention, member.handle);
      });
      node.appendChild(item);
    });
    // Below the caret, approximated by the composer's bounds.
    const rect = textarea.getBoundingClientRect();
    node.style.left = rect.left + 8 + 'px';
    node.style.bottom = window.innerHeight - rect.top + 4 + 'px';
    document.body.appendChild(node);
    popover = node;
  }

  function navigate(event) {
    if (!popover) return;
    const items = popover.querySelectorAll('.mention-pop-item');
    if (items.length === 0) return;
    let index = Array.from(items).indexOf(popover.querySelector('.mention-pop-item.active'));
    if (event.key === 'ArrowDown') {
      event.preventDefault();
      index = (index + 1) % items.length;
    } else if (event.key === 'ArrowUp') {
      event.preventDefault();
      index = (index - 1 + items.length) % items.length;
    } else if (event.key === 'Enter' || event.key === 'Tab') {
      event.preventDefault();
      const handle = items[index]?.dataset?.handle;
      const textarea = event.target instanceof HTMLTextAreaElement ? event.target : document.querySelector('.panel-input textarea');
      const mention = handle && textarea ? mentionOf(textarea) : null;
      if (mention) complete(textarea, mention, handle);
      return;
    } else {
      if (event.key === 'Escape') close();
      return;
    }
    items.forEach((item) => item.classList.remove('active'));
    items[index].classList.add('active');
  }

  return {
    mount() {
      document.addEventListener('input', (event) => {
        const textarea = event.target;
        if (!(textarea instanceof HTMLTextAreaElement) || !textarea.closest('.panel-input')) return;
        const mention = mentionOf(textarea);
        if (mention) show(textarea, mention);
        else close();
      });
      document.addEventListener('keydown', navigate, true);
      document.addEventListener('click', (event) => {
        if (popover && !popover.contains(event.target) && !(event.target instanceof HTMLTextAreaElement)) close();
      });
    },
  };
}
