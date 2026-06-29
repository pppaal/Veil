import { test, expect } from '@playwright/test';

// Phase AN: register a fresh handle and confirm we land on the main
// app shell. The demo persists session state in IndexedDB so each
// test gets a clean storage state via Playwright's storageState reset.

test.describe('VEIL web demo — auth', () => {
  test('registers a fresh handle and shows the main app', async ({ page, context }) => {
    await context.clearCookies();
    await page.goto('./');
    // The auth screen shows the brand mark plus a register form.
    await expect(page.locator('#auth-screen')).toBeVisible();
    await expect(page.locator('#app')).toBeHidden();

    // Fresh handle so reruns don't collide.
    const handle = `e2e${Date.now().toString(36).slice(-7)}`;
    await page.fill('#reg-name', 'E2E Tester');
    await page.fill('#reg-handle', handle);
    await page.click('#reg-btn');

    // After register → challenge → verify, the auth screen hides and
    // the main app is mounted.
    await expect(page.locator('#app')).toBeVisible();
    await expect(page.locator('#auth-screen')).toBeHidden();

    // Conn pill flips out of "연결 중…" once the WS upgrades.
    await expect(page.locator('#conn-pill')).not.toContainText('연결 중', {
      timeout: 10_000,
    });
  });

  test('rejects invalid handle shapes client-side', async ({ page }) => {
    await page.goto('./');
    await page.fill('#reg-name', 'E2E');
    // Uppercase + dash — invalid by the input pattern attribute.
    await page.fill('#reg-handle', 'BadHandle-1');
    await page.click('#reg-btn');
    // We should still be on the auth screen — the form's pattern
    // refused to submit.
    await expect(page.locator('#auth-screen')).toBeVisible();
  });
});
