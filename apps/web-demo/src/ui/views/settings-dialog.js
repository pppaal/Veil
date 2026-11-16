// Settings: theme, sounds, browser notifications and their content level,
// and the list of blocked accounts. Also the sound toggle the menu and
// Ctrl/Cmd+Shift+S share.

import { t } from '../../../i18n/i18n.js';
import { shownHandle } from '../../domain/handles.js';
import { NOTIFICATION_LEVELS } from '../../features/notifications.js';
import { applyThemeClass, avatarFor, el, handleLine } from '../dom.js';
import { toast } from '../toast.js';

const NOTIFICATION_LEVEL_LABEL_KEYS = {
  off: 'settings.notifications.off',
  generic: 'settings.notifications.generic',
  sender: 'settings.notifications.sender',
  sender_preview: 'settings.notifications.senderPreview',
};

function select(key, label, options, value) {
  const node = el('select', { class: 'settings-select', dataset: { key }, 'aria-label': label },
    options.map(([optionValue, optionLabel]) => el('option', { value: optionValue }, [optionLabel])));
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
    const line = (key) => el('div', { class: 'blocked-empty' }, [t(key)]);
    safety.listBlocked().then((users) => {
      if (users === null) {
        container.replaceChildren(line('settings.blockedLoadFailed'));
        return;
      }
      if (users.length === 0) {
        container.replaceChildren(line('settings.blockedEmpty'));
        return;
      }
      container.replaceChildren(...users.map((user) => {
        const unblock = el('button', { class: 'text-btn unblock' }, [t('settings.unblock')]);
        const blockedRow = el('div', { class: 'blocked-row' }, [
          avatarFor(user.handle ?? '?', 'sm'),
          el('div', { class: 'grow' }, [handleLine(user.handle)]),
          unblock,
        ]);
        unblock.addEventListener('click', async () => {
          // A refused unblock keeps the row: the account is still blocked.
          if (!(await safety.unblock(user.userId ?? user.id, shownHandle(user.handle)))) return;
          blockedRow.remove();
          if (!container.querySelector('.blocked-row')) container.replaceChildren(line('settings.blockedEmpty'));
        });
        return blockedRow;
      }));
    });
    return el('div', { class: 'settings-section', dataset: { blockedSection: '1' } }, [
      el('div', { class: 'settings-label' }, [t('settings.blocked')]),
      container,
    ]);
  }

  async function requestNotifications() {
    if (!('Notification' in window)) {
      toast(t('notifications.unsupported'), 'error');
      return;
    }
    if (Notification.permission === 'granted') {
      toast(t('notifications.alreadyOn'), 'good');
      return;
    }
    if (Notification.permission === 'denied') {
      toast(t('notifications.blockedInBrowser'), 'error');
      return;
    }
    const result = await Notification.requestPermission();
    toast(t(result === 'granted' ? 'notifications.on' : 'notifications.denied'), result === 'granted' ? 'good' : 'error');
  }

  return {
    toggleSounds() {
      setSounds(!state.soundsEnabled);
      toast(t(state.soundsEnabled ? 'sounds.on' : 'sounds.off'), 'good');
    },

    open() {
      document.getElementById('settings-dialog')?.remove();
      const theme = select('theme', t('settings.theme'), [['dark', t('settings.theme.dark')], ['light', t('settings.theme.light')]],
        document.documentElement.classList.contains('theme-light') ? 'light' : 'dark');
      const level = select('notification-level', t('settings.notifications.level'),
        NOTIFICATION_LEVELS.map((value) => [value, t(NOTIFICATION_LEVEL_LABEL_KEYS[value])]),
        preferences.notificationLevel());
      const sounds = el('input', { type: 'checkbox', role: 'switch', class: 'settings-toggle', 'aria-label': t('settings.sounds'), dataset: { key: 'sounds' } });
      sounds.checked = !!state.soundsEnabled;
      const notifications = el('button', { class: 'btn btn-ghost', dataset: { key: 'notif' } }, [t('settings.notifications.allow')]);
      const closeButton = el('button', { class: 'btn btn-primary', id: 'settings-close' }, [t('settings.close')]);
      const backdrop = el('div', { id: 'settings-dialog', class: 'dialog-backdrop', role: 'presentation' }, [
        el('div', { class: 'dialog', role: 'dialog', 'aria-modal': 'true', 'aria-labelledby': 'settings-title' }, [
          el('div', { class: 'dialog-title', id: 'settings-title' }, [t('menu.settings')]),
          row(t('settings.theme'), theme),
          row(t('settings.sounds'), sounds),
          row(t('settings.notifications'), notifications),
          row(t('settings.notifications.level'), level),
          blockedSection(),
          el('div', { class: 'dialog-actions' }, [closeButton]),
        ]),
      ]);
      document.body.appendChild(backdrop);

      theme.addEventListener('change', () => {
        applyThemeClass(theme.value === 'light');
        preferences.setTheme(theme.value);
      });
      level.addEventListener('change', () => {
        if (!preferences.setNotificationLevel(level.value)) toast(t('settings.saveFailed'), 'error');
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
