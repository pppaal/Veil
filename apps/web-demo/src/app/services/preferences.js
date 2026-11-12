// What this browser remembers outside the session: theme, sounds, muted
// conversations, notification content, and which notices were dismissed.
// All of it sits in localStorage under 'veil-' keys, which a wipe removes,
// and none of it is key, session or message state.

import { readNotificationLevel, writeNotificationLevel } from '../../features/notifications.js';

const THEME_KEY = 'veil-demo-theme';
const SOUND_KEY = 'veil-demo-sounds-enabled-v1';
const MUTE_KEY = 'veil-demo-muted-convs-v1';
const BETA_BANNER_KEY = 'veil-demo-beta-banner-dismissed-v1';
const NOTIF_PROMPT_KEY = 'veil-demo-notif-prompt-dismissed-v1';

// Storage access throws in some sandboxed and privacy modes.
export function webStorage(name) {
  try {
    return window[name];
  } catch {
    return null;
  }
}

export function createPreferences(storage = webStorage('localStorage')) {
  const read = (key) => {
    try {
      return storage?.getItem(key) ?? null;
    } catch {
      return null;
    }
  };
  const write = (key, value) => {
    try {
      storage.setItem(key, value);
    } catch {}
  };

  return {
    lightTheme: () => read(THEME_KEY) === 'light',
    setTheme: (theme) => write(THEME_KEY, theme),

    soundsEnabled: () => read(SOUND_KEY) === '1',
    setSoundsEnabled: (enabled) => write(SOUND_KEY, enabled ? '1' : '0'),

    mutedConversations() {
      try {
        return new Set(JSON.parse(read(MUTE_KEY) || '[]'));
      } catch {
        return new Set();
      }
    },
    setMutedConversations: (ids) => write(MUTE_KEY, JSON.stringify(Array.from(ids))),

    betaBannerDismissed: () => read(BETA_BANNER_KEY) === '1',
    dismissBetaBanner: () => write(BETA_BANNER_KEY, '1'),

    notificationPromptDismissed: () => read(NOTIF_PROMPT_KEY) === '1',
    dismissNotificationPrompt: () => write(NOTIF_PROMPT_KEY, '1'),

    notificationLevel: () => readNotificationLevel(storage),
    // False when it could not be saved.
    setNotificationLevel: (level) => writeNotificationLevel(storage, level),
  };
}
