// Keyboard shortcuts across the app, and focus kept inside an open dialog.
// Esc and the help binding work everywhere; the rest skip while the user
// types in a field.

import { $ } from '../dom.js';

const FOCUSABLE = 'a[href], button:not([disabled]), input:not([disabled]), textarea:not([disabled]), select:not([disabled]), [tabindex]:not([tabindex="-1"])';

const isTypingTarget = (target) => Boolean(target) && (target.tagName === 'INPUT' || target.tagName === 'TEXTAREA' || target.isContentEditable);

// openHelp(), toggleSounds(): what Ctrl/Cmd+/ and Ctrl/Cmd+Shift+S do.
export function createShortcuts({ openHelp, toggleSounds }) {
  function onKey(event) {
    const mod = event.ctrlKey || event.metaKey;
    // Esc closes an open dialog, else the menu. A dialog that handled Esc
    // itself (a confirmation) has closed already; without this check the
    // dialog it was stacked on would close with it.
    if (event.key === 'Escape' && !event.defaultPrevented) {
      const open = document.querySelector('.dialog-backdrop:not(.hidden)') ?? document.querySelector('.menu:not(.hidden)');
      if (open) {
        event.preventDefault();
        open.classList.add('hidden');
        return;
      }
    }
    if (mod && (event.key === '/' || event.key === '?')) {
      event.preventDefault();
      openHelp();
      return;
    }
    if (isTypingTarget(event.target)) return;
    if (mod && (event.key === 'k' || event.key === 'K')) {
      event.preventDefault();
      const search = $('search-input');
      if (search) {
        search.focus();
        search.select?.();
      }
    } else if (mod && (event.key === 'n' || event.key === 'N')) {
      event.preventDefault();
      $('new-chat-btn')?.click();
    } else if (mod && event.shiftKey && (event.key === 's' || event.key === 'S')) {
      event.preventDefault();
      toggleSounds();
    }
  }

  // Tab and Shift+Tab cycle within the open dialog.
  function trapTab(event) {
    if (event.key !== 'Tab') return;
    const open = document.querySelector('.dialog-backdrop:not(.hidden) .dialog');
    if (!open) return;
    const focusable = open.querySelectorAll(FOCUSABLE);
    if (focusable.length === 0) return;
    const first = focusable[0];
    const last = focusable[focusable.length - 1];
    if (event.shiftKey && document.activeElement === first) {
      event.preventDefault();
      last.focus();
    } else if (!event.shiftKey && document.activeElement === last) {
      event.preventDefault();
      first.focus();
    }
  }

  return {
    mount() {
      document.addEventListener('keydown', onKey);
      document.addEventListener('keydown', trapTab);
    },
  };
}
