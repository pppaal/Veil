// The keyboard shortcuts dialog (Ctrl/Cmd+/ or the menu). Built once, on
// first open, and kept in the page after that.

import { el } from '../dom.js';

const SHORTCUTS = [
  { label: '대화 검색', sequence: ['Ctrl/Cmd', 'K'] },
  { label: '새 대화', sequence: ['Ctrl/Cmd', 'N'] },
  { label: '대화 안에서 찾기', sequence: ['Ctrl/Cmd', 'F'] },
  { label: '도움말 열기', sequence: ['Ctrl/Cmd', '/'] },
  { label: '사운드 토글', sequence: ['Ctrl/Cmd', 'Shift', 'S'] },
  { label: '다이얼로그 / 메뉴 닫기', sequence: ['Esc'] },
  { label: '메시지 전송 (입력창)', sequence: ['Enter'] },
  { label: '입력창에서 줄바꿈', sequence: ['Shift', 'Enter'] },
];

function build(soundsEnabled) {
  const grid = el('div', { class: 'help-grid' });
  for (const shortcut of SHORTCUTS) {
    const keys = shortcut.sequence.flatMap((key, index) => (index === 0 ? [el('kbd', {}, [key])] : [' + ', el('kbd', {}, [key])]));
    grid.append(el('div', { class: 'seq' }, keys), el('div', {}, [shortcut.label]));
  }
  const dialog = el('div', { id: 'help-dialog', class: 'dialog-backdrop hidden', role: 'presentation' }, [
    el('div', { class: 'dialog', role: 'dialog', 'aria-modal': 'true', 'aria-labelledby': 'help-title' }, [
      el('div', { class: 'dialog-title', id: 'help-title' }, ['키보드 단축키']),
      el('div', { class: 'dialog-sub' }, ['VEIL 을 더 빠르게 쓰는 법.']),
      grid,
      el('div', { class: 'dialog-sub', style: 'margin-top:14px;font-size:11px;opacity:0.6' }, [
        `${soundsEnabled ? '🔊' : '🔇'} 사운드: ${soundsEnabled ? '켜짐' : '꺼짐'} (메뉴 또는 Ctrl/Cmd+Shift+S)`,
      ]),
      el('div', { class: 'dialog-actions' }, [el('button', { class: 'btn btn-primary', id: 'help-ok' }, ['확인'])]),
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
