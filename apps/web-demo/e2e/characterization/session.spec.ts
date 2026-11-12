import { expect, test } from '@playwright/test';

import {
  closeAll,
  expectNoErrors,
  openDevice,
  openMenuItem,
  register,
  relay,
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
    await expect(toast(device, '핸들을 입력하세요')).toBeVisible();
    await page.fill('#reg-handle', 'Bad-Handle');
    await page.click('#reg-btn');
    await expect(toast(device, '소문자, 숫자, _ 만 사용 (최대 32자)')).toBeVisible();
    await expect(page.locator('#auth-screen')).toBeVisible();
    await expect(page.locator('#restore-row')).toBeHidden();

    await page.fill('#reg-handle', device.handle.toUpperCase());
    await page.click('#reg-btn');
    await expect(page.locator('#app')).toBeVisible();
    await expect(page.locator('#auth-screen')).toBeHidden();
    await expect(toast(device, `환영합니다 @${device.handle}`)).toBeVisible();
    await expect(page.locator('#sidebar-me')).toContainText(`@${device.handle}`);
    await expect(page.locator('#sidebar-me')).toContainText(/기기 [0-9a-f]{8}/);
    await expect(page.locator('#legacy-banner')).toBeHidden();
    // No realtime gateway on the relay: the app stays in polling mode.
    await expect(page.locator('#conn-pill')).toContainText('연결 실패', { timeout: 15_000 });
    await expect(page.locator('#conv-list .conv-empty')).toHaveText('대화 없음. + 새 대화 버튼으로 시작하세요.');
    await expect(page.locator('#panels .panel-empty .empty-title')).toHaveText('대화를 골라주세요');

    await openMenuItem(device, 'ws-info');
    await expect(toast(device, '연결: 폴링 (4초)')).toBeVisible();

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
    await expect(page.locator('#restore-btn')).toHaveText('다시 시도');

    await page.click('#restore-btn');
    await expect(toast(device, '복원 실패:')).toBeVisible();
    await expect(page.locator('#restore-rejected')).toBeVisible();

    await page.reload();
    await expect(toast(device, '세션 복원 실패:')).toBeVisible();
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

  test('wipe deletes the identity and everything VEIL stored', async ({ browser }) => {
    const device = await register(browser, `cal${id}`);
    devices.push(device);
    const { page } = device;

    await openMenuItem(device, 'wipe');
    await expect(page.locator('#confirm-title')).toHaveText('이 신원 삭제');
    await page.click('#confirm-cancel');
    await expect(page.locator('#app')).toBeVisible();

    await openMenuItem(device, 'wipe');
    await expect(page.locator('#confirm-body')).toContainText(`@${device.handle} 의 키와 이 브라우저의 VEIL 데이터를 전부 삭제합니다`);
    await page.click('#confirm-ok');
    await expect(page.locator('#auth-screen')).toBeVisible();
    await expect(toast(device, '키를 삭제했습니다')).toBeVisible();
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

  test('settings keep theme, sounds and notification content, and switch the language', async ({ browser }) => {
    const device = await register(browser, `dee${id}`);
    devices.push(device);
    const { page } = device;
    const stored = (key: string) => page.evaluate((name) => localStorage.getItem(name), key);

    await openMenuItem(device, 'open-settings');
    const dialog = page.locator('#settings-dialog');
    await expect(dialog).toBeVisible();
    await expect(dialog.locator('#settings-title')).toHaveText('⚙️ 설정');
    await expect(dialog.locator('.settings-label')).toHaveText([
      '테마',
      '언어 (재로드 필요)',
      '사운드 (수신/전송 톤)',
      '브라우저 알림',
      '알림 내용',
      '차단된 사용자',
    ]);
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
    await expect(help.locator('#help-title')).toHaveText('키보드 단축키');
    await expect(help.locator('.help-grid > div:not(.seq)')).toHaveText([
      '대화 검색',
      '새 대화',
      '대화 안에서 찾기',
      '도움말 열기',
      '사운드 토글',
      '다이얼로그 / 메뉴 닫기',
      '메시지 전송 (입력창)',
      '입력창에서 줄바꿈',
    ]);
    await expect(help).toContainText('🔊 사운드: 켜짐');
    await page.keyboard.press('Escape');
    await expect(help).toBeHidden();

    await page.keyboard.press('ControlOrMeta+Shift+S');
    await expect(page.locator('#toast-root .toast', { hasText: '사운드 꺼짐' })).toBeVisible();
    expect(await stored('veil-demo-sounds-enabled-v1')).toBe('0');

    await reload(device);
    await expect(page.locator('html')).toHaveClass(/theme-light/);

    await openMenuItem(device, 'open-settings');
    await Promise.all([page.waitForEvent('load'), page.locator('[data-key="lang"]').selectOption('en')]);
    await expect(page.locator('#app')).toBeVisible();
    await expect(page.locator('html')).toHaveAttribute('lang', 'en');
    await expect(page.locator('#menu [data-action="copy-handle"]')).toHaveText('copy my handle');
    await expect(page.locator('#new-chat-title')).toHaveText('new direct chat');
    await expect(page.locator('#menu [data-action="open-settings"]')).toHaveText('⚙️ 설정');

    await openMenuItem(device, 'open-settings');
    await expect(page.locator('#settings-dialog .settings-label').nth(4)).toHaveText('Notification content');
    await Promise.all([page.waitForEvent('load'), page.locator('[data-key="lang"]').selectOption('ko')]);
    await expect(page.locator('#app')).toBeVisible();
    await expect(page.locator('html')).toHaveAttribute('lang', 'ko');
    await expect(page.locator('#menu [data-action="copy-handle"]')).toHaveText('내 핸들 복사');
    expectNoErrors(device);
  });

  test('the menu offers its actions in order', async () => {
    const { page } = devices.at(-1) as Device;
    await expect(page.locator('#menu > *')).toHaveCount(9);
    await expect(page.locator('#menu .menu-item')).toHaveText([
      '내 핸들 복사',
      '연결 상태',
      '다른 기기로 이전',
      '🔔 사운드 토글',
      '⌨️ 단축키',
      '⚙️ 설정',
      '📥 카카오톡 가져오기',
      '로그아웃 + 키 삭제',
    ]);
  });
});
