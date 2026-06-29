import { test, expect, Browser, BrowserContext, Page } from '@playwright/test';

async function registerAndOpen(
  browser: Browser,
  displayName: string,
  handle: string,
): Promise<{ context: BrowserContext; page: Page }> {
  const context = await browser.newContext();
  const page = await context.newPage();
  await page.goto('./');
  await page.fill('#reg-name', displayName);
  await page.fill('#reg-handle', handle);
  await page.click('#reg-btn');
  await expect(page.locator('#app')).toBeVisible();
  await expect(page.locator('#conn-pill')).not.toContainText('연결 중', {
    timeout: 10_000,
  });
  return { context, page };
}

test.describe('VEIL web demo — message actions', () => {
  test('edit + delete round-trip with realtime fanout', async ({ browser }) => {
    const stamp = Date.now().toString(36).slice(-6);
    const senderHandle = `snd${stamp}`;
    const recvHandle = `rcv${stamp}`;

    const sender = await registerAndOpen(browser, 'Sender', senderHandle);
    const recv = await registerAndOpen(browser, 'Receiver', recvHandle);

    // Open chat from sender's side.
    await sender.page.click('#new-chat-btn');
    await sender.page.fill('#new-peer-input', recvHandle);
    await sender.page.click('#new-confirm');

    await expect(sender.page.locator('.conv-list')).toContainText(`@${recvHandle}`);
    const ta = sender.page.locator('.panel-input textarea').first();
    await ta.fill('original body');
    await ta.press('Enter');

    // Confirm sender bubble shows.
    const myBubble = sender.page.locator('.msg-row.me').first();
    await expect(myBubble).toContainText('original body', { timeout: 5_000 });

    // Recipient receives.
    await expect(recv.page.locator('.conv-list')).toContainText(`@${senderHandle}`, {
      timeout: 10_000,
    });
    await recv.page.click(`text=@${senderHandle}`);
    await expect(recv.page.locator('.msg-row.them')).toContainText('original body', {
      timeout: 10_000,
    });

    // Right-click on sender's own message to open the action menu and
    // hit edit. We programmatically dispatch the contextmenu to avoid
    // race issues with Playwright's right-click flake on Linux.
    await myBubble.dispatchEvent('contextmenu');
    await expect(sender.page.locator('.msg-action-menu')).toBeVisible();

    // Stub window.prompt so the test doesn't block on the native dialog.
    await sender.page.evaluate(() => {
      // eslint-disable-next-line no-undef
      (window as any).prompt = () => 'edited body';
    });

    await sender.page.locator('.msg-action-menu .msg-action-item:has-text("수정")').click();

    // Edit lands locally + propagates to recv via WS.
    await expect(myBubble.locator('.msg-edited')).toBeVisible({ timeout: 5_000 });
    await expect(myBubble).toContainText('edited body');
    await expect(recv.page.locator('.msg-row.them .msg-text')).toContainText(
      'edited body',
      { timeout: 10_000 },
    );

    // Delete: open menu again, click delete, confirm.
    await myBubble.dispatchEvent('contextmenu');
    await expect(sender.page.locator('.msg-action-menu')).toBeVisible();
    await sender.page.locator('.msg-action-menu .danger:has-text("삭제")').click();
    // Confirm dialog
    await sender.page.locator('#confirm-ok').click();

    await expect(myBubble).toContainText('🚫 삭제된 메시지', { timeout: 5_000 });
    await expect(recv.page.locator('.msg-row.them')).toContainText('🚫 삭제된 메시지', {
      timeout: 10_000,
    });

    await sender.context.close();
    await recv.context.close();
  });
});
