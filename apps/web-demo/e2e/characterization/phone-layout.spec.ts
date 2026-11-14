import { expect, test } from '@playwright/test';

import { closeAll, expectNoErrors, relay, rowOf, send, stamp, watchErrors, type Device } from './support';

// At phone width the list and the chat take turns on the one screen: the
// chat that opens must be inside the viewport (it once sat in a second grid
// column, off the right edge), and the back button must bring the list back.

test.describe('phone-width layout', () => {
  const id = stamp();
  let phone: Device;

  test.beforeAll(async ({ browser }) => {
    await relay('/__test/reset');
    const peerContext = await browser.newContext({ locale: 'ko-KR' });
    const peerPage = await peerContext.newPage();
    await peerPage.goto('./', { waitUntil: 'networkidle' });
    await peerPage.fill('#reg-handle', `ppeer${id}`);
    await peerPage.click('#reg-btn');
    await expect(peerPage.locator('#app')).toBeVisible();
    await peerContext.close();

    const context = await browser.newContext({ locale: 'ko-KR', viewport: { width: 390, height: 844 } });
    const page = await context.newPage();
    phone = { handle: `pphone${id}`, context, page, errors: [] };
    watchErrors(page, phone.errors);
    await page.goto('./', { waitUntil: 'networkidle' });
    await page.fill('#reg-handle', phone.handle);
    await page.click('#reg-btn');
    await expect(page.locator('#app')).toBeVisible();
  });

  test.afterAll(async () => {
    await closeAll(phone);
  });

  test('the open chat and its composer are on screen, and back returns to the list', async () => {
    const { page } = phone;
    await expect(page.locator('.sidebar')).toBeInViewport();

    await page.click('#new-chat-btn');
    await page.fill('#new-peer-input', `ppeer${id}`);
    await page.click('#new-confirm');
    await expect(page.locator('.panel .panel-title .name')).toHaveText(`@ppeer${id}`);
    await expect(page.locator('.panel .panel-title .name')).toBeInViewport();
    await expect(page.locator('.panel-input textarea')).toBeInViewport();

    await send(phone, 'visible on a phone');
    await expect(rowOf(phone, 'visible on a phone')).toBeInViewport();
    await expect(page.locator('.sidebar')).toBeHidden();

    await page.click('#back-to-list');
    await expect(page.locator('.sidebar')).toBeInViewport();
    await expect(page.locator('.conv-item', { hasText: `@ppeer${id}` })).toBeInViewport();
    expectNoErrors(phone);
  });
});
