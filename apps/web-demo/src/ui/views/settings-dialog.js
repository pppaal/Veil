// Settings: theme, language, sounds, browser notifications and their
// content level, and the list of blocked users. Also the sound toggle the
// menu and Ctrl/Cmd+Shift+S share.

import { activeLang, setLang, t } from '../../../i18n/i18n.js';
import { shownHandle } from '../../domain/handles.js';
import { NOTIFICATION_LEVELS } from '../../features/notifications.js';
import { avatarFor, el, handleLine } from '../dom.js';
import { toast } from '../toast.js';

const NOTIFICATION_LEVEL_LABEL_KEYS = {
  off: 'settings.notifications.off',
  generic: 'settings.notifications.generic',
  sender: 'settings.notifications.sender',
  sender_preview: 'settings.notifications.senderPreview',
};

function select(key, options, value) {
  const node = el('select', { class: 'settings-select', dataset: { key } },
    options.map(([optionValue, label]) => el('option', { value: optionValue }, [label])));
  node.value = value;
  return node;
}

const row = (label, control) => el('div', { class: 'settings-row' }, [el('div', { class: 'settings-label' }, [label]), control]);

// preferences: src/app/services/preferences.js; safety: src/app/services/safety.js.
export function createSettingsDialog({ store, preferences, safety }) {
  const { state } = store;

  function setSounds(enabled) {
    state.soundsEnabled = enabled;
    preferences.setSoundsEnabled(enabled);
  }

  // Filled in once the server has answered.
  function blockedSection() {
    const container = el('div', { class: 'blocked-list', id: 'blocked-list-container' });
    safety.listBlocked().then((users) => {
      container.replaceChildren(...users.map((user) => {
        const unblock = el('button', { class: 'unblock' }, ['해제']);
        const blockedRow = el('div', { class: 'blocked-row' }, [
          avatarFor(user.handle ?? '?', 'sm'),
          el('div', { class: 'grow' }, [handleLine(user.handle, 'font-size:13px')]),
          unblock,
        ]);
        unblock.addEventListener('click', async () => {
          await safety.unblock(user.userId ?? user.id, shownHandle(user.handle));
          blockedRow.remove();
        });
        return blockedRow;
      }));
    });
    return el('div', { dataset: { blockedSection: '1' }, style: 'margin-top:10px;border-top:1px solid rgba(255,255,255,0.06);padding-top:10px' }, [
      el('div', { class: 'settings-label', style: 'margin-bottom:6px' }, ['차단된 사용자']),
      container,
    ]);
  }

  async function requestNotifications() {
    if (!('Notification' in window)) {
      toast('알림 미지원 브라우저', 'error');
      return;
    }
    if (Notification.permission === 'granted') {
      toast('이미 켜짐', 'good');
      return;
    }
    if (Notification.permission === 'denied') {
      toast('브라우저 설정에서 풀어주세요', 'error');
      return;
    }
    const result = await Notification.requestPermission();
    toast(result === 'granted' ? '알림 켜짐' : '알림 거부됨', result === 'granted' ? 'good' : 'error');
  }

  return {
    toggleSounds() {
      setSounds(!state.soundsEnabled);
      toast(state.soundsEnabled ? '사운드 켜짐' : '사운드 꺼짐', 'good');
    },

    open() {
      document.getElementById('settings-dialog')?.remove();
      const theme = select('theme', [['dark', '다크'], ['light', '라이트']],
        document.documentElement.classList.contains('theme-light') ? 'light' : 'dark');
      const lang = select('lang', [['ko', '한국어'], ['en', 'English'], ['ja', '日本語']], activeLang());
      const level = select('notification-level',
        NOTIFICATION_LEVELS.map((value) => [value, t(NOTIFICATION_LEVEL_LABEL_KEYS[value])]),
        preferences.notificationLevel());
      const sounds = el('input', { type: 'checkbox', class: 'settings-toggle', dataset: { key: 'sounds' } });
      sounds.checked = !!state.soundsEnabled;
      const notifications = el('button', { class: 'btn btn-ghost', dataset: { key: 'notif' } }, ['권한 요청']);
      const closeButton = el('button', { class: 'btn btn-primary', id: 'settings-close' }, ['닫기']);
      const backdrop = el('div', { id: 'settings-dialog', class: 'dialog-backdrop', role: 'presentation' }, [
        el('div', { class: 'dialog', role: 'dialog', 'aria-modal': 'true', 'aria-labelledby': 'settings-title', style: 'width:380px;max-width:92vw' }, [
          el('div', { class: 'dialog-title', id: 'settings-title' }, ['⚙️ 설정']),
          el('div', { class: 'dialog-sub', style: 'margin-bottom:12px' }, ['VEIL 의 모든 토글을 한 곳에.']),
          row('테마', theme),
          row('언어 (재로드 필요)', lang),
          row('사운드 (수신/전송 톤)', sounds),
          row('브라우저 알림', notifications),
          row(t('settings.notifications.level'), level),
          blockedSection(),
          el('div', { class: 'dialog-actions', style: 'margin-top:14px' }, [closeButton]),
        ]),
      ]);
      document.body.appendChild(backdrop);

      theme.addEventListener('change', () => {
        document.documentElement.classList.toggle('theme-light', theme.value === 'light');
        preferences.setTheme(theme.value);
      });
      lang.addEventListener('change', () => setLang(lang.value));
      level.addEventListener('change', () => {
        if (!preferences.setNotificationLevel(level.value)) toast('설정을 저장하지 못했어요', 'error');
      });
      sounds.addEventListener('change', () => setSounds(sounds.checked));
      notifications.addEventListener('click', requestNotifications);
      const close = () => backdrop.remove();
      closeButton.addEventListener('click', close);
      backdrop.addEventListener('click', (event) => {
        if (event.target === backdrop) close();
      });
      closeButton.focus();
    },
  };
}
