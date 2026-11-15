import { expect, test } from '@playwright/test';

import {
  closeAll,
  expectNoErrors,
  openDevice,
  openMenuItem,
  register,
  relay,
  relayState,
  reload,
  stamp,
  toast,
  type Device,
} from './support';

// Signing up and back in, a session the relay rejects, wiping, and the
// preferences a device keeps.

test.describe.configure({ mode: 'serial' });

test.describe('session lifecycle', () => {
  const id = stamp();
  const devices: Device[] = [];

  test.beforeAll(async () => {
    await relay('/__test/reset');
  });

  test.afterAll(async () => {
    await closeAll(...devices);
  });

  test('registers a handle and signs in again after a reload', async ({ browser }) => {
    const device = await openDevice(browser, `ann${id}`);
    devices.push(device);
    const { page } = device;

    await page.click('#reg-btn');
    await expect(toast(device, 'Enter a handle')).toBeVisible();
    await page.fill('#reg-handle', 'Bad-Handle');
    await page.click('#reg-btn');
    await expect(toast(device, 'Lowercase letters, digits and underscores only, up to 32 characters')).toBeVisible();
    await expect(page.locator('#auth-screen')).toBeVisible();
    await expect(page.locator('#restore-row')).toBeHidden();

    await page.fill('#reg-handle', device.handle.toUpperCase());
    await page.click('#reg-btn');
    await expect(page.locator('#app')).toBeVisible();
    await expect(page.locator('#auth-screen')).toBeHidden();
    await expect(toast(device, `Welcome, @${device.handle}`)).toBeVisible();
    // The relay stores the device's name and platform and can read them:
    // both are the same for every browser, never the browser's platform
    // string (navigator.platform), which names the operating system. The
    // relay has no platform value for a browser; 'android' stands in.
    const browserPlatform = await page.evaluate(() => navigator.platform);
    const stored = await relayState<{ deviceName: string; platform: string }[]>(`/__test/devices/${device.handle}`);
    expect(stored).toEqual([{ deviceName: 'Veil Web', platform: 'android' }]);
    expect(stored[0].deviceName).not.toContain(browserPlatform);
    await expect(page.locator('#sidebar-me')).toContainText(`@${device.handle}`);
    await expect(page.locator('#legacy-banner')).toBeHidden();
    // No realtime gateway on the relay: the app stays in polling mode, and
    // the bar says so in its one word for a missing live connection.
    await expect(page.locator('#conn-status')).toHaveText('Offline', { timeout: 15_000 });
    await expect(page.locator('#conv-list .conv-empty')).toHaveText('No chats yet. Start one with New chat.');
    await expect(page.locator('#panels .panel-empty .empty-title')).toHaveText('Choose a chat');
    // English whatever the browser's language (the context is ko-KR).
    await expect(page.locator('html')).toHaveAttribute('lang', 'en');

    await openMenuItem(device, 'ws-info');
    await expect(toast(device, 'Connection: polling every 4 seconds')).toBeVisible();

    await reload(device);
    await expect(page.locator('#sidebar-me')).toContainText(`@${device.handle}`);
    expectNoErrors(device);
  });

  test('refuses a handle that is taken', async ({ browser }) => {
    const device = await openDevice(browser, devices[0].handle);
    devices.push(device);
    await device.page.fill('#reg-handle', device.handle);
    await device.page.click('#reg-btn');
    await expect(toast(device, 'Handle is already taken')).toBeVisible();
    await expect(device.page.locator('#auth-screen')).toBeVisible();
    await expect(device.page.locator('#restore-row')).toBeHidden();
    expectNoErrors(device);
  });

  // The relay revokes the device: a refresh and a fresh challenge are both
  // refused, so the session ends, and the keys stay for a retry.
  test('a session the relay rejects returns to the auth screen with the keys kept', async ({ browser }) => {
    const device = await register(browser, `bea${id}`);
    devices.push(device);
    const { page } = device;
    await relay('/__test/revoke', { handle: device.handle });

    await expect(page.locator('#auth-screen')).toBeVisible({ timeout: 15_000 });
    await expect(page.locator('#restore-row')).toBeVisible();
    await expect(page.locator('#restore-handle')).toHaveText(`@${device.handle}`);
    await expect(page.locator('#restore-rejected')).toBeVisible();
    await expect(page.locator('#restore-btn')).toHaveText('Try again');

    await page.click('#restore-btn');
    await expect(toast(device, 'Could not sign in:')).toBeVisible();
    await expect(page.locator('#restore-rejected')).toBeVisible();

    await page.reload();
    await expect(toast(device, 'Could not sign in to the saved account:')).toBeVisible();
    await expect(page.locator('#auth-screen')).toBeVisible();
    await expect(page.locator('#restore-rejected')).toBeVisible();
    await expect(page.locator('#restore-handle')).toHaveText(`@${device.handle}`);

    // A new handle over a stored identity asks first; cancelling keeps it.
    await page.fill('#reg-handle', `other${id}`);
    await page.click('#reg-btn');
    await expect(page.locator('#confirm-dialog')).toBeVisible();
    await expect(page.locator('#confirm-body')).toContainText(`@${device.handle}`);
    await page.click('#confirm-cancel');
    await expect(page.locator('#confirm-dialog')).toBeHidden();
    await expect(page.locator('#restore-handle')).toHaveText(`@${device.handle}`);
    expectNoErrors(device);
  });

  test('wipe deletes the identity and everything Veil stored', async ({ browser }) => {
    const device = await register(browser, `cal${id}`);
    devices.push(device);
    const { page } = device;

    await openMenuItem(device, 'wipe');
    await expect(page.locator('#confirm-title')).toHaveText('Delete this identity');
    await page.click('#confirm-cancel');
    await expect(page.locator('#app')).toBeVisible();

    await openMenuItem(device, 'wipe');
    await expect(page.locator('#confirm-body')).toContainText(`This deletes @${device.handle}'s keys and all Veil data in this browser`);
    await page.click('#confirm-ok');
    await expect(page.locator('#auth-screen')).toBeVisible();
    await expect(toast(device, 'Keys deleted')).toBeVisible();
    await expect(page.locator('#restore-row')).toBeHidden();
    // The auth screen opens the database again to look for an identity,
    // so it exists, with every store empty.
    const left = await page.evaluate(async () => {
      const database = await new Promise<IDBDatabase>((resolve, reject) => {
        const request = indexedDB.open('veil-demo');
        request.onsuccess = () => resolve(request.result);
        request.onerror = () => reject(request.error);
      });
      const rows: number[] = [];
      for (const name of database.objectStoreNames) {
        rows.push(await new Promise<number>((resolve) => {
          const count = database.transaction(name).objectStore(name).count();
          count.onsuccess = () => resolve(count.result);
        }));
      }
      database.close();
      return {
        storage: Object.keys(localStorage).filter((key) => key.startsWith('veil-')),
        stores: database.objectStoreNames.length,
        rows: rows.reduce((sum, count) => sum + count, 0),
      };
    });
    expect(left.storage).toEqual([]);
    expect(left.stores).toBeGreaterThan(0);
    expect(left.rows).toBe(0);

    await page.reload();
    await expect(page.locator('#auth-screen')).toBeVisible();
    await expect(page.locator('#restore-row')).toBeHidden();
    expectNoErrors(device);
  });

  test('settings keep theme, sounds and notification content', async ({ browser }) => {
    const device = await register(browser, `dee${id}`);
    devices.push(device);
    const { page } = device;
    const stored = (key: string) => page.evaluate((name) => localStorage.getItem(name), key);

    await openMenuItem(device, 'open-settings');
    const dialog = page.locator('#settings-dialog');
    await expect(dialog).toBeVisible();
    await expect(dialog.locator('#settings-title')).toHaveText('Settings');
    // No language row: the app is English only.
    await expect(dialog.locator('.settings-label')).toHaveText([
      'Theme',
      'Sounds',
      'Browser notifications',
      'Notification content',
      'Blocked users',
    ]);
    await expect(dialog.locator('[data-key="lang"]')).toHaveCount(0);
    await expect(dialog.locator('[data-key="notification-level"]')).toHaveValue('generic');
    await dialog.locator('[data-key="theme"]').selectOption('light');
    await expect(page.locator('html')).toHaveClass(/theme-light/);
    await dialog.locator('[data-key="sounds"]').check();
    await dialog.locator('[data-key="notification-level"]').selectOption('sender');
    expect(await stored('veil-demo-theme')).toBe('light');
    expect(await stored('veil-demo-sounds-enabled-v1')).toBe('1');
    expect(await stored('veil-demo-notification-level-v1')).toBe('sender');
    await dialog.locator('#settings-close').click();
    await expect(dialog).toHaveCount(0);

    await page.keyboard.press('ControlOrMeta+/');
    const help = page.locator('#help-dialog');
    await expect(help).toBeVisible();
    await expect(help.locator('#help-title')).toHaveText('Keyboard shortcuts');
    await expect(help.locator('.help-grid > div:not(.seq)')).toHaveText([
      'Search chats',
      'New chat',
      'Find in chat',
      'Open this help',
      'Sounds on or off',
      'Close a dialog or menu',
      'Send the message',
      'New line in the message',
    ]);
    await expect(help).toContainText('Sounds: on');
    await page.keyboard.press('Escape');
    await expect(help).toBeHidden();

    await page.keyboard.press('ControlOrMeta+Shift+S');
    await expect(page.locator('#toast-root .toast', { hasText: 'Sounds off' })).toBeVisible();
    expect(await stored('veil-demo-sounds-enabled-v1')).toBe('0');

    await reload(device);
    await expect(page.locator('html')).toHaveClass(/theme-light/);
    // The page stays English: nothing stored or in the URL picks a language.
    await expect(page.locator('html')).toHaveAttribute('lang', 'en');
    await expect(page.locator('#menu [data-action="copy-handle"]')).toHaveText('Copy my handle');
    await expect(page.locator('#new-chat-title')).toHaveText('New chat');
    expectNoErrors(device);
  });

  test('the menu offers its actions in order', async () => {
    const { page } = devices.at(-1) as Device;
    await expect(page.locator('#menu > *')).toHaveCount(9);
    await expect(page.locator('#menu .menu-item')).toHaveText([
      'Copy my handle',
      'Connection status',
      'Move to another device',
      'Sounds',
      'Keyboard shortcuts',
      'Settings',
      'Import a KakaoTalk export',
      'Sign out and delete keys',
    ]);
  });
});
