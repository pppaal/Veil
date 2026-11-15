// The keyboard shortcuts dialog (Ctrl/Cmd+/ or the menu). Built once, on
// first open, and kept in the page after that.

import { el } from '../dom.js';

const SHORTCUTS = [
  { label: 'Search chats', sequence: ['Ctrl/Cmd', 'K'] },
  { label: 'New chat', sequence: ['Ctrl/Cmd', 'N'] },
  { label: 'Find in chat', sequence: ['Ctrl/Cmd', 'F'] },
  { label: 'Open this help', sequence: ['Ctrl/Cmd', '/'] },
  { label: 'Sounds on or off', sequence: ['Ctrl/Cmd', 'Shift', 'S'] },
  { label: 'Close a dialog or menu', sequence: ['Esc'] },
  { label: 'Send the message', sequence: ['Enter'] },
  { label: 'New line in the message', sequence: ['Shift', 'Enter'] },
];

function build(soundsEnabled) {
  const grid = el('div', { class: 'help-grid' });
  for (const shortcut of SHORTCUTS) {
    const keys = shortcut.sequence.flatMap((key, index) => (index === 0 ? [el('kbd', {}, [key])] : [' + ', el('kbd', {}, [key])]));
    grid.append(el('div', { class: 'seq' }, keys), el('div', {}, [shortcut.label]));
  }
  const dialog = el('div', { id: 'help-dialog', class: 'dialog-backdrop hidden', role: 'presentation' }, [
    el('div', { class: 'dialog', role: 'dialog', 'aria-modal': 'true', 'aria-labelledby': 'help-title' }, [
      el('div', { class: 'dialog-title', id: 'help-title' }, ['Keyboard shortcuts']),
      grid,
      el('div', { class: 'help-note' }, [`Sounds: ${soundsEnabled ? 'on' : 'off'} (menu or Ctrl/Cmd+Shift+S)`]),
      el('div', { class: 'dialog-actions' }, [el('button', { class: 'btn btn-primary', id: 'help-ok' }, ['OK'])]),
    ]),
  ]);
  dialog.querySelector('#help-ok').addEventListener('click', () => dialog.classList.add('hidden'));
  dialog.addEventListener('click', (event) => {
    if (event.target === dialog) dialog.classList.add('hidden');
  });
  return dialog;
}

export function createHelpDialog({ store }) {
  return {
    open() {
      let dialog = document.getElementById('help-dialog');
      if (!dialog) {
        dialog = build(store.state.soundsEnabled);
        document.body.appendChild(dialog);
      }
      dialog.classList.remove('hidden');
      dialog.querySelector('#help-ok')?.focus();
    },
  };
}
