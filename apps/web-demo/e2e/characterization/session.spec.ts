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

    // What is wrong with the handle shows under the field, in place of its
    // hint and in the danger colour, until the handle changes; it is never
    // a toast, so tapping again does not stack them.
    const field = page.locator('#reg-handle');
    const hint = page.locator('#reg-handle-hint');
    await expect(field).toHaveAttribute('aria-describedby', 'reg-handle-hint');
    await expect(hint).toHaveText("You can't change it later.");
    await page.click('#reg-btn');
    await page.click('#reg-btn');
    await expect(hint).toHaveText('Enter a handle');
    await expect(hint).toHaveClass(/field-error/);
    await expect(field).toHaveAttribute('aria-invalid', 'true');
    await expect(page.locator('#toast-root .toast')).toHaveCount(0);
    const dangerRgb = await page.evaluate(() => {
      const probe = document.body.appendChild(document.createElement('span'));
      probe.style.color = 'var(--danger)';
      const rgb = getComputedStyle(probe).color;
      probe.remove();
      return rgb;
    });
    await expect(hint).toHaveCSS('color', dangerRgb);
    await page.fill('#reg-handle', 'Bad-Handle');
    await expect(hint).toHaveText("You can't change it later.");
    await expect(hint).not.toHaveClass(/field-error/);
    await expect(field).not.toHaveAttribute('aria-invalid');
    await page.click('#reg-btn');
    await expect(hint).toHaveText('Use 3 to 32 lowercase letters, numbers, dots or underscores.');
    // The server's rules, one at a time.
    for (const [typed, said] of [
      ['ab', 'Use 3 to 32 lowercase letters, numbers, dots or underscores.'],
      ['_sam', 'Start and end with a letter or number.'],
      ['sam.', 'Start and end with a letter or number.'],
      ['sa..m', "Don't put 2 dots or underscores in a row."],
      ['sa._m', "Don't put 2 dots or underscores in a row."],
    ]) {
      await page.fill('#reg-handle', typed);
      await page.click('#reg-btn');
      await expect(hint).toHaveText(said);
    }
    await expect(page.locator('#toast-root .toast')).toHaveCount(0);
    await expect(page.locator('#auth-screen')).toBeVisible();
    await expect(page.locator('#restore-row')).toBeHidden();
    // Nothing is stored yet, so there is nothing to remove.
    await expect(page.locator('#wipe-btn')).toBeHidden();

    await page.fill('#reg-handle', device.handle.toUpperCase());
    await page.click('#reg-btn');
    await expect(page.locator('#app')).toBeVisible();
    await expect(page.locator('#auth-screen')).toBeHidden();
    await expect(page.locator('.topbar-name')).toHaveText('Chats');
    // The relay stores the device's name and platform and can read them:
    // both are the same for every browser, never the browser's platform
    // string (navigator.platform), which names the operating system. The
    // relay has no platform value for a browser; 'android' stands in.
    const browserPlatform = await page.evaluate(() => navigator.platform);
    const stored = await relayState<{ deviceName: string; platform: string }[]>(`/__test/devices/${device.handle}`);
    expect(stored).toEqual([{ deviceName: 'Veil Web', platform: 'android' }]);
    expect(stored[0].deviceName).not.toContain(browserPlatform);
    await expect(page.locator('#menu-me')).toContainText(`@${device.handle}`);
    await expect(page.locator('#legacy-banner')).toBeHidden();
    // No realtime gateway on the relay: the app stays in polling mode, and
    // the bar says so in its one word for a missing live connection.
    await expect(page.locator('#conn-status')).toHaveText('Offline', { timeout: 15_000 });
    await expect(page.locator('#conv-list .conv-empty .conv-empty-title')).toHaveText('No chats yet');
    await expect(page.locator('#conv-list .conv-empty button')).toHaveText('New chat');
    await expect(page.locator('#panels .panel-empty .empty-title')).toHaveText('Select a chat');
    // English whatever the browser's language (the context is ko-KR).
    await expect(page.locator('html')).toHaveAttribute('lang', 'en');

    // The connection shows in the bar only: the menu has no item for it.
    await expect(page.locator('#menu [data-action="ws-info"]')).toHaveCount(0);

    await reload(device);
    await expect(page.locator('#menu-me')).toContainText(`@${device.handle}`);
    expectNoErrors(device);
  });

  test('refuses a handle that is taken', async ({ browser }) => {
    const device = await openDevice(browser, devices[0].handle);
    devices.push(device);
    await device.page.fill('#reg-handle', device.handle);
    await device.page.click('#reg-btn');
    await expect(device.page.locator('#reg-handle-hint')).toHaveText('That handle is taken. Try another.');
    await expect(device.page.locator('#reg-handle')).toHaveAttribute('aria-invalid', 'true');
    await expect(device.page.locator('#toast-root .toast')).toHaveCount(0);
    await expect(device.page.locator('#auth-screen')).toBeVisible();
    await expect(device.page.locator('#restore-row')).toBeHidden();
    expectNoErrors(device);
  });

  // The form checks the server's rules, no narrower: a dot is allowed.
  test('registers any handle the server takes, dots included', async ({ browser }) => {
    const device = await register(browser, `ann.${id}`);
    devices.push(device);
    await expect(device.page.locator('#menu-me')).toContainText(`@ann.${id}`);
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
    // One notice says what happened and offers both ways out; the row's
    // Continue and the line under it give way to it.
    await expect(page.locator('#restore-rejected-text')).toHaveText(
      `Couldn't sign in as @${device.handle}. This browser may have been removed from the account.`,
    );
    await expect(page.locator('#restore-retry')).toHaveText('Try again');
    await expect(page.locator('#restore-remove')).toHaveText('Remove from this browser');
    await expect(page.locator('#restore-btn')).toBeHidden();
    await expect(page.locator('#wipe-btn')).toBeHidden();

    await page.click('#restore-retry');
    await expect(toast(device, "Couldn't sign in. Try again.")).toBeVisible();
    await expect(page.locator('#restore-rejected')).toBeVisible();

    await page.reload();
    await expect(toast(device, "Couldn't sign in to the saved account. Try again.")).toBeVisible();
    await expect(page.locator('#auth-screen')).toBeVisible();
    await expect(page.locator('#restore-rejected')).toBeVisible();
    await expect(page.locator('#restore-handle')).toHaveText(`@${device.handle}`);

    // A new handle over a stored identity asks first; cancelling keeps it.
    await page.fill('#reg-handle', `other${id}`);
    await page.click('#reg-btn');
    await expect(page.locator('#confirm-dialog')).toBeVisible();
    await expect(page.locator('#confirm-title')).toHaveText(`Remove @${device.handle} from this browser?`);
    await expect(page.locator('#confirm-body')).toContainText(`@${device.handle}`);
    await page.click('#confirm-cancel');
    await expect(page.locator('#confirm-dialog')).toBeHidden();
    await expect(page.locator('#restore-handle')).toHaveText(`@${device.handle}`);
    expectNoErrors(device);
  });

  test('sign out deletes the identity and everything Veil stored', async ({ browser }) => {
    const device = await register(browser, `cal${id}`);
    devices.push(device);
    const { page } = device;

    await openMenuItem(device, 'wipe');
    await expect(page.locator('#confirm-title')).toHaveText(`Sign out of @${device.handle}?`);
    await expect(page.locator('#confirm-ok')).toHaveText('Sign out');
    await page.click('#confirm-cancel');
    await expect(page.locator('#app')).toBeVisible();

    // The safe way out: moving the account instead.
    await openMenuItem(device, 'wipe');
    await page.click('#confirm-alt');
    await expect(page.locator('#transfer-old-dialog')).toBeVisible();
    await page.click('#transfer-old-cancel');
    await expect(page.locator('#transfer-old-dialog')).toBeHidden();

    await openMenuItem(device, 'wipe');
    await expect(page.locator('#confirm-body')).toHaveText(
      `This deletes your keys and messages from this browser. There's no backup, so you can't sign in as @${device.handle} again.`,
    );
    await expect(page.locator('#confirm-alt')).toHaveText('Move to another device');
    await page.click('#confirm-ok');
    await expect(page.locator('#auth-screen')).toBeVisible();
    await expect(toast(device, 'Signed out')).toBeVisible();
    await expect(page.locator('#restore-row')).toBeHidden();
    await expect(page.locator('#wipe-btn')).toBeHidden();
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
    // Grouped sections; no language row: the app is English only.
    await expect(dialog.locator('.settings-section-title')).toHaveText(['Appearance', 'Notifications', 'Blocked accounts']);
    await expect(dialog.locator('.settings-label')).toHaveText(['Theme', 'Web notifications', 'Show', 'Sounds']);
    await expect(dialog.locator('.settings-footer')).toHaveText('Notifications only appear while Veil is open in a tab.');
    await expect(dialog.locator('#settings-close')).toHaveText('Done');
    await expect(dialog.locator('[data-key="lang"]')).toHaveCount(0);
    // The theme follows the system until one is chosen.
    await expect(dialog.locator('[data-key="theme"]')).toHaveValue('system');
    await expect(dialog.locator('[data-key="theme"] option')).toHaveText(['System', 'Light', 'Dark']);
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
    await expect(help.locator('.settings-section-title')).toHaveText(['Navigation', 'Messages']);
    await expect(help.locator('.help-grid > div:not(.seq)')).toHaveText([
      'Search',
      'New chat',
      'Find in chat',
      'Keyboard shortcuts',
      'Close',
      'Send',
      'New line',
      'Sounds on or off',
    ]);
    // The keys of this platform (not a Mac), never "Ctrl/Cmd", and no notes.
    await expect(help.locator('.help-grid .seq').first()).toHaveText('CtrlK');
    await expect(help).not.toContainText('Ctrl/Cmd');
    await expect(help.locator('#help-ok')).toHaveText('Done');
    await page.keyboard.press('Escape');
    await expect(help).toBeHidden();

    await page.keyboard.press('ControlOrMeta+Shift+S');
    await expect(page.locator('#toast-root .toast', { hasText: 'Sounds off' })).toBeVisible();
    expect(await stored('veil-demo-sounds-enabled-v1')).toBe('0');

    await reload(device);
    await expect(page.locator('html')).toHaveClass(/theme-light/);
    // The page stays English: nothing stored or in the URL picks a language.
    await expect(page.locator('html')).toHaveAttribute('lang', 'en');
    await expect(page.locator('#menu [data-action="copy-handle"]')).toHaveAttribute('aria-label', 'Copy handle');
    await expect(page.locator('#new-chat-title')).toHaveText('New chat');
    expectNoErrors(device);
  });

  test('the menu offers its actions in order', async () => {
    const { page } = devices.at(-1) as Device;
    // The account with its copy button, then the items, Sign out last.
    await expect(page.locator('#menu > *')).toHaveCount(8);
    await expect(page.locator('#menu > :first-child')).toHaveId('menu-me');
    await expect(page.locator('#menu .menu-item')).toHaveText([
      'Settings',
      'Keyboard shortcuts',
      'Move to another device…',
      'Import from KakaoTalk…',
      'Sign out…',
    ]);
    await expect(page.locator('#menu .menu-item').last()).toHaveClass(/menu-danger/);
  });
});
