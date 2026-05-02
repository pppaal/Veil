import { test, expect, Browser, BrowserContext, Page } from '@playwright/test';

// Round-trip: Alice and Bob both register, Alice opens a direct chat,
// Bob receives the message, decrypts, and the bubble shows the
// plaintext on Bob's side. Two browser contexts simulate two devices.

async function registerAndOpen(
  browser: Browser,
  displayName: string,
  handle: string,
): Promise<{ context: BrowserContext; page: Page }> {
  const context = await browser.newContext();
  const page = await context.newPage();
  await page.goto('/');
  await page.fill('#reg-name', displayName);
  await page.fill('#reg-handle', handle);
  await page.click('#reg-btn');
  await expect(page.locator('#app')).toBeVisible();
  await expect(page.locator('#conn-pill')).not.toContainText('연결 중', {
    timeout: 10_000,
  });
  return { context, page };
}

test.describe('VEIL web demo — messaging', () => {
  test('Alice → Bob round-trip with markdown', async ({ browser }) => {
    const stamp = Date.now().toString(36).slice(-6);
    const aliceHandle = `alice${stamp}`;
    const bobHandle = `bob${stamp}`;

    const alice = await registerAndOpen(browser, 'Alice', aliceHandle);
    const bob = await registerAndOpen(browser, 'Bob', bobHandle);

    // Alice opens a new chat with Bob.
    await alice.page.click('#new-chat-btn');
    await alice.page.fill('#new-peer-input', bobHandle);
    await alice.page.click('#new-confirm');

    // Wait for conversation list to surface in Alice's sidebar.
    await expect(alice.page.locator('.conv-list')).toContainText(`@${bobHandle}`, {
      timeout: 5_000,
    });

    // Type a message with markdown into Alice's active panel.
    const aliceTextarea = alice.page.locator('.panel-input textarea').first();
    await aliceTextarea.fill('hello *world* and `code`');
    await aliceTextarea.press('Enter');

    // Alice sees her own bubble with the plaintext.
    await expect(alice.page.locator('.msg-row.me .msg-text')).toContainText('hello', {
      timeout: 5_000,
    });
    await expect(alice.page.locator('.msg-row.me .msg-text strong')).toHaveText('world');
    await expect(alice.page.locator('.msg-row.me .msg-text code')).toHaveText('code');

    // Bob's sidebar gains the conversation; click into it.
    await expect(bob.page.locator('.conv-list')).toContainText(`@${aliceHandle}`, {
      timeout: 10_000,
    });
    await bob.page.click(`text=@${aliceHandle}`);

    // Bob's incoming bubble should decrypt and render the markdown too.
    await expect(bob.page.locator('.msg-row.them .msg-text')).toContainText('hello', {
      timeout: 10_000,
    });
    await expect(bob.page.locator('.msg-row.them .msg-text strong')).toHaveText('world');

    await alice.context.close();
    await bob.context.close();
  });
});
