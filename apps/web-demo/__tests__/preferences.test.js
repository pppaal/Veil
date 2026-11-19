import { describe, expect, it } from 'vitest';

import { createPreferences } from '../src/app/services/preferences.js';

function memoryStorage(entries = {}) {
  const map = new Map(Object.entries(entries));
  return {
    getItem: (key) => (map.has(key) ? map.get(key) : null),
    setItem: (key, value) => map.set(key, String(value)),
    entries: () => Object.fromEntries(map),
  };
}

const throwingStorage = {
  getItem() {
    throw new Error('denied');
  },
  setItem() {
    throw new Error('denied');
  },
};

describe('preferences', () => {
  it('keep every setting under its veil- key, as earlier builds wrote them', () => {
    const storage = memoryStorage();
    const preferences = createPreferences(storage);
    preferences.setTheme('light');
    preferences.setSoundsEnabled(true);
    preferences.setMutedConversations(new Set(['c1', 'c2']));
    preferences.dismissNotificationPrompt();
    expect(preferences.setNotificationLevel('sender')).toBe(true);
    expect(storage.entries()).toEqual({
      'veil-demo-theme': 'light',
      'veil-demo-sounds-enabled-v1': '1',
      'veil-demo-muted-convs-v1': '["c1","c2"]',
      'veil-demo-notif-prompt-dismissed-v1': '1',
      'veil-demo-notification-level-v1': 'sender',
    });
    expect(preferences.theme()).toBe('light');
    expect(preferences.soundsEnabled()).toBe(true);
    expect([...preferences.mutedConversations().keys()]).toEqual(['c1', 'c2']);
    expect(preferences.notificationPromptDismissed()).toBe(true);
    expect(preferences.notificationLevel()).toBe('sender');
    preferences.setSoundsEnabled(false);
    expect(storage.entries()['veil-demo-sounds-enabled-v1']).toBe('0');
  });

  it('keep when a timed mute ends, and forget it once it has', () => {
    const storage = memoryStorage();
    const preferences = createPreferences(storage);
    const end = Date.now() + 3_600_000;
    preferences.setMutedConversations(new Map([['c1', null], ['c2', end]]));
    expect(storage.entries()['veil-demo-muted-convs-v1']).toBe(JSON.stringify(['c1', ['c2', end]]));
    expect([...preferences.mutedConversations()]).toEqual([['c1', null], ['c2', end]]);
    expect([...preferences.mutedConversations(end)]).toEqual([['c1', null]]);
  });

  it('fall back to the defaults when storage is missing, refuses, or holds garbage', () => {
    for (const storage of [null, throwingStorage, memoryStorage({ 'veil-demo-muted-convs-v1': '{not json' })]) {
      const preferences = createPreferences(storage);
      // With nothing chosen the theme follows the system.
      expect(preferences.theme()).toBe('system');
      expect(preferences.soundsEnabled()).toBe(false);
      expect(preferences.mutedConversations().size).toBe(0);
      expect(preferences.notificationLevel()).toBe('generic');
      expect(() => preferences.setTheme('light')).not.toThrow();
    }
    expect(createPreferences(throwingStorage).setNotificationLevel('sender')).toBe(false);
  });
});
