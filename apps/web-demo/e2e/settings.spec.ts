import { test, expect } from '@playwright/test';

test.describe('VEIL web demo — settings + shortcuts', () => {
  test('opens settings dialog from menu and toggles theme', async ({ page }) => {
    await page.goto('/');
    const handle = `cfg${Date.now().toString(36).slice(-7)}`;
    await page.fill('#reg-name', 'Cfg Tester');
    await page.fill('#reg-handle', handle);
    await page.click('#reg-btn');
    await expect(page.locator('#app')).toBeVisible();

    // Open the menu and click "⚙️ 설정". The button is injected by the
    // polish module, so we wait for it to appear.
    await page.click('#menu-btn');
    const settingsItem = page.locator('[data-action="open-settings"]');
    await expect(settingsItem).toBeVisible({ timeout: 5_000 });
    await settingsItem.click();

    await expect(page.locator('#settings-dialog')).toBeVisible();

    // Default theme is dark — switch to light and verify the
    // documentElement gets the .theme-light class.
    await page.selectOption('[data-key="theme"]', 'light');
    await expect(page.locator('html')).toHaveClass(/theme-light/);

    // Switch back to confirm the toggle is reversible.
    await page.selectOption('[data-key="theme"]', 'dark');
    await expect(page.locator('html')).not.toHaveClass(/theme-light/);
  });

  test('Ctrl/Cmd+/ opens the keyboard shortcuts dialog', async ({ page }) => {
    await page.goto('/');
    const handle = `kbd${Date.now().toString(36).slice(-7)}`;
    await page.fill('#reg-name', 'Kbd');
    await page.fill('#reg-handle', handle);
    await page.click('#reg-btn');
    await expect(page.locator('#app')).toBeVisible();

    // Modifier varies by OS; Playwright's "Meta" handles macOS, "Control"
    // handles Linux/Windows. We use "ControlOrMeta" via keyboard.press.
    await page.keyboard.press('ControlOrMeta+/');
    await expect(page.locator('#help-dialog')).toBeVisible({ timeout: 5_000 });
    await expect(page.locator('#help-dialog')).toContainText('키보드 단축키');

    await page.locator('#help-ok').click();
    await expect(page.locator('#help-dialog')).toBeHidden();
  });
});
