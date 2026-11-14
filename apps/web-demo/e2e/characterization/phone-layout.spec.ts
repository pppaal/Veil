import { readFileSync } from 'node:fs';

import { expect, test, type Locator } from '@playwright/test';

import { closeAll, expectNoErrors, relay, rowOf, send, stamp, watchErrors, type Device } from './support';

// At phone width the list and the chat take turns on the one screen: the
// chat that opens must be inside the viewport (it once sat in a second grid
// column, off the right edge), and the back button must bring the list back.
// The composer is a narrow box there, and what its placeholder says must
// still fit in it.

test.describe.configure({ mode: 'serial' });

const LOCALES = ['ko', 'en', 'ja'];

// Every reason a frozen composer gives (src/ui/views/chat-view.js), in every
// language the app ships.
function frozenReasons(): string[] {
  return LOCALES.flatMap((locale) => {
    const strings = JSON.parse(readFileSync(new URL(`../../i18n/${locale}.json`, import.meta.url), 'utf8')) as Record<string, string>;
    return Object.entries(strings)
      .filter(([key]) => key.endsWith('.composerFrozen'))
      .map(([, text]) => text);
  });
}

// Whether a textarea shows its whole placeholder: the height the text takes
// when wrapped at the box's inner width, against the box's inner height.
function placeholderFits(textarea: Locator): Promise<boolean> {
  return textarea.evaluate((node: HTMLTextAreaElement) => {
    const style = getComputedStyle(node);
    const inner = (size: number, before: string, after: string) => size - parseFloat(before) - parseFloat(after);
    const mirror = document.createElement('div');
    mirror.textContent = node.placeholder;
    mirror.style.cssText = 'position:absolute;visibility:hidden;white-space:pre-wrap;overflow-wrap:break-word';
    mirror.style.font = style.font;
    mirror.style.lineHeight = style.lineHeight;
    mirror.style.width = `${inner(node.clientWidth, style.paddingLeft, style.paddingRight)}px`;
    document.body.append(mirror);
    const needed = mirror.getBoundingClientRect().height;
    mirror.remove();
    return needed <= inner(node.clientHeight, style.paddingTop, style.paddingBottom) + 0.5;
  });
}

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

  test('the composer placeholder is never cut off', async () => {
    const { page } = phone;
    await page.locator('.conv-item', { hasText: `@ppeer${id}` }).click();
    const textarea = page.locator('.panel-input textarea');
    // The panel is still in the page while the list covers it: wait for it
    // to be shown before measuring it.
    await expect(textarea).toBeInViewport();
    // No key hint on a phone: beside the four buttons it took two lines of a
    // one-line box.
    await expect(textarea).toHaveAttribute('placeholder', '메시지 입력');
    expect(await placeholderFits(textarea)).toBe(true);

    // A frozen composer is a disabled one whose placeholder says why.
    // Reaching one takes a relay that rewrites its lists (relay-lists.spec.ts);
    // the layout treats every reason alike, so each is put on this composer,
    // at this width and at the narrowest phones still in use.
    const reasons = frozenReasons();
    expect(reasons.length).toBeGreaterThanOrEqual(LOCALES.length * 5);
    for (const width of [390, 360]) {
      await page.setViewportSize({ width, height: 844 });
      for (const reason of reasons) {
        await textarea.evaluate((node: HTMLTextAreaElement, text) => {
          node.disabled = true;
          node.placeholder = text;
        }, reason);
        expect(await placeholderFits(textarea), `${width}px: ${reason}`).toBe(true);
      }
      // The buttons of a composer that sends nothing give their room to it.
      await expect(page.locator('.panel-input > button:visible')).toHaveCount(0);
      await expect(textarea).toBeDisabled();
    }
    expectNoErrors(phone);
  });
});
