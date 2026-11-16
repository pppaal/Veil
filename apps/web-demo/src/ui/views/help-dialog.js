// The keyboard shortcuts dialog (the modifier and / or the menu), in two
// groups, with the keys of the user's platform. Built once, on first open,
// and kept in the page after that.

import { t } from '../../../i18n/i18n.js';
import { el } from '../dom.js';
import { modifierKey } from '../keys.js';

const MOD = Symbol('modifier');

const GROUPS = [
  ['help.navigation', [
    ['help.search', [MOD, 'K']],
    ['newChat.title', [MOD, 'N']],
    ['chat.find', [MOD, 'F']],
    ['help.open', [MOD, '/']],
    ['help.close', ['Esc']],
  ]],
  ['help.messages', [
    ['help.send', ['Enter']],
    ['help.newLine', ['Shift', 'Enter']],
    ['help.sounds', [MOD, 'Shift', 'S']],
  ]],
];

function build() {
  const sections = GROUPS.map(([titleKey, shortcuts]) => {
    const grid = el('div', { class: 'help-grid' });
    for (const [labelKey, sequence] of shortcuts) {
      const keys = sequence.map((key) => el('kbd', {}, [key === MOD ? modifierKey() : key]));
      grid.append(el('div', {}, [t(labelKey)]), el('div', { class: 'seq' }, keys));
    }
    return el('div', { class: 'help-group' }, [el('div', { class: 'settings-section-title' }, [t(titleKey)]), grid]);
  });
  const dialog = el('div', { id: 'help-dialog', class: 'dialog-backdrop hidden', role: 'presentation' }, [
    el('div', { class: 'dialog', role: 'dialog', 'aria-modal': 'true', 'aria-labelledby': 'help-title' }, [
      el('div', { class: 'dialog-title', id: 'help-title' }, [t('menu.shortcuts')]),
      ...sections,
      el('div', { class: 'dialog-actions' }, [el('button', { class: 'btn btn-primary', id: 'help-ok' }, [t('help.done')])]),
    ]),
  ]);
  dialog.querySelector('#help-ok').addEventListener('click', () => dialog.classList.add('hidden'));
  dialog.addEventListener('click', (event) => {
    if (event.target === dialog) dialog.classList.add('hidden');
  });
  return dialog;
}

export function createHelpDialog() {
  return {
    open() {
      let dialog = document.getElementById('help-dialog');
      if (!dialog) {
        dialog = build();
        document.body.appendChild(dialog);
      }
      dialog.classList.remove('hidden');
      dialog.querySelector('#help-ok')?.focus();
    },
  };
}
