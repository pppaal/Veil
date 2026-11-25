// What this browser remembers outside the session: theme (light, dark or the
// system's, the default), sounds, muted conversations and when each mute
// ends, notification content, and which notices were dismissed.
// All of it sits in localStorage under 'veil-' keys, which a wipe removes,
// and none of it is key, session or message state.

import { muteEntries, storedMutes } from '../../domain/mute.js';
import { readNotificationLevel, writeNotificationLevel } from '../../features/notifications.js';

const THEME_KEY = 'veil-demo-theme';
const SOUND_KEY = 'veil-demo-sounds-enabled-v1';
const MUTE_KEY = 'veil-demo-muted-convs-v1';
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
    theme() {
      const stored = read(THEME_KEY);
      return stored === 'light' || stored === 'dark' ? stored : 'system';
    },
    setTheme: (theme) => write(THEME_KEY, theme),

    soundsEnabled: () => read(SOUND_KEY) === '1',
    setSoundsEnabled: (enabled) => write(SOUND_KEY, enabled ? '1' : '0'),

    // convId -> when the mute ends (ms), or null for one with no end.
    mutedConversations(nowMs = Date.now()) {
      try {
        return muteEntries(JSON.parse(read(MUTE_KEY) || '[]'), nowMs);
      } catch {
        return new Map();
      }
    },
    setMutedConversations: (mutes) => write(MUTE_KEY, JSON.stringify(storedMutes(mutes))),

    notificationPromptDismissed: () => read(NOTIF_PROMPT_KEY) === '1',
    dismissNotificationPrompt: () => write(NOTIF_PROMPT_KEY, '1'),

    notificationLevel: () => readNotificationLevel(storage),
    // False when it could not be saved.
    setNotificationLevel: (level) => writeNotificationLevel(storage, level),
  };
}
