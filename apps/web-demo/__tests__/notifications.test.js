import { describe, expect, it } from 'vitest';

import {
  buildNotification,
  DEFAULT_NOTIFICATION_LEVEL,
  NOTIFICATION_LEVEL_KEY,
  readNotificationLevel,
  writeNotificationLevel,
} from '../src/features/notifications.js';

function memoryStorage(initial = {}) {
  const map = new Map(Object.entries(initial));
  return {
    getItem: (key) => (map.has(key) ? map.get(key) : null),
    setItem: (key, value) => { map.set(key, String(value)); },
    map,
  };
}

const throwingStorage = {
  getItem: () => { throw new Error('SecurityError'); },
  setItem: () => { throw new Error('QuotaExceededError'); },
};

const message = { senderHandle: 'alice', preview: 'meet at 6 by the north gate', conversationId: 'c-1' };

describe('notification levels', () => {
  it('defaults to generic and ignores unknown or unreadable values', () => {
    expect(DEFAULT_NOTIFICATION_LEVEL).toBe('generic');
    expect(readNotificationLevel(memoryStorage())).toBe('generic');
    expect(readNotificationLevel(memoryStorage({ [NOTIFICATION_LEVEL_KEY]: 'everything' }))).toBe('generic');
    expect(readNotificationLevel(throwingStorage)).toBe('generic');
    expect(readNotificationLevel(null)).toBe('generic');
  });

  it('stores valid levels under a veil- key and survives storage errors', () => {
    const storage = memoryStorage();
    expect(writeNotificationLevel(storage, 'sender_preview')).toBe(true);
    expect(NOTIFICATION_LEVEL_KEY.startsWith('veil-')).toBe(true);
    expect(readNotificationLevel(storage)).toBe('sender_preview');
    expect(writeNotificationLevel(storage, 'loud')).toBe(false);
    expect(readNotificationLevel(storage)).toBe('sender_preview');
    expect(writeNotificationLevel(throwingStorage, 'off')).toBe(false);
  });

  it('generic shows neither sender nor content', () => {
    const content = buildNotification({ level: 'generic', ...message });
    expect(content).toEqual({ title: 'VEIL', body: 'New message', tag: 'veil' });
    expect(JSON.stringify(content)).not.toContain('alice');
    expect(JSON.stringify(content)).not.toContain('north gate');
    expect(JSON.stringify(content)).not.toContain('c-1');
    expect(buildNotification({ level: 'unknown', ...message })).toEqual(content);
  });

  it('adds the sender, then the preview, only when asked', () => {
    expect(buildNotification({ level: 'off', ...message })).toBeNull();
    expect(buildNotification({ level: 'sender', ...message })).toEqual({ title: '@alice', body: 'New message', tag: 'veil-c-1' });
    expect(buildNotification({ level: 'sender_preview', ...message }))
      .toEqual({ title: '@alice', body: 'meet at 6 by the north gate', tag: 'veil-c-1' });
  });

  it('uses localized labels', () => {
    const labels = { appName: 'VEIL', newMessage: '새 메시지' };
    expect(buildNotification({ level: 'generic', ...message, labels }).body).toBe('새 메시지');
    expect(buildNotification({ level: 'sender', ...message, senderHandle: undefined, labels }).title).toBe('VEIL');
  });
});
