import { expect, test } from '@playwright/test';

import { relay, watchErrors } from './support';

// The one-time secret page (s.html): a secret sealed in the browser, opened
// once by whoever holds the link, and gone after that.

test.describe('one-time secret links', () => {
  test.beforeAll(async () => {
    await relay('/__test/reset');
  });

  test('a link opens its secret once', async ({ browser }) => {
    const errors: string[] = [];
    const sender = await browser.newContext({ locale: 'ko-KR' });
    const composer = await sender.newPage();
    watchErrors(composer, errors);
    await composer.goto('./s.html');
    await expect(composer.locator('#compose')).toBeVisible();
    await composer.fill('#secret', 'the vault code is 4711');
    await composer.click('#genBtn');
    await expect(composer.locator('#out')).toBeVisible();
    const link = (await composer.locator('#linkText').innerText()).trim();
    expect(link).toMatch(/\/demo\/s\.html#[0-9a-f-]{36}\.k2\.[A-Za-z0-9_-]{43}$/);

    const recipient = await browser.newContext({ locale: 'ko-KR' });
    const viewer = await recipient.newPage();
    watchErrors(viewer, errors);
    await viewer.goto(link);
    await expect(viewer.locator('#view')).toBeVisible();
    await expect(viewer.locator('#passPrompt')).toBeHidden();
    await viewer.click('#revealBtn');
    await expect(viewer.locator('#revealText')).toHaveText('the vault code is 4711');
    await expect(viewer.locator('#viewTitle')).toHaveText('비밀 메시지');
    expect(new URL(viewer.url()).hash).toBe('');
    // A production relay serves only the viewer under /demo/, so the page
    // points at the public site, never at the demo.
    await expect(viewer.locator('.cta a')).toHaveAttribute('href', 'https://pppaal.github.io/Veil/');
    await expect(viewer.locator('.cta a')).toHaveAttribute('rel', 'noreferrer');

    const late = await recipient.newPage();
    watchErrors(late, errors);
    await late.goto(link);
    await late.click('#revealBtn');
    await expect(late.locator('#goneMsg')).toHaveText('이미 열렸거나 만료된 링크입니다');

    expect(errors).toEqual([]);
    await sender.close();
    await recipient.close();
  });
});
