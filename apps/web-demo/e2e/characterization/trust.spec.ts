import { expect, test, type Page } from '@playwright/test';

import {
  bubbleTexts,
  closeAll,
  expectNoErrors,
  register,
  relay,
  send,
  stamp,
  startChat,
  toast,
  type Device,
} from './support';

// Where trust decisions reach the user: the safety-number dialog, and the
// banner a key the pins do not admit raises, with its decline and accept
// paths, for a contact that was verified and one that was not. The banner
// stops nothing: the conversation keeps sending to the key it already has.

test.describe.configure({ mode: 'serial' });

async function openSafetyDialog(page: Page) {
  await page.locator('.panel-header button[aria-label="Safety number"]').click();
  const dialog = page.locator('#safety-dialog');
  await expect(dialog).toBeVisible();
  return dialog;
}

test.describe('a contact verified by safety number', () => {
  const id = stamp();
  let alice: Device;
  let bob: Device;

  test.beforeAll(async ({ browser }) => {
    await relay('/__test/reset');
    alice = await register(browser, `talice${id}`);
    bob = await register(browser, `tbob${id}`);
    await startChat(alice, bob);
    await send(alice, 'first contact');
    await expect.poll(() => bubbleTexts(bob), { timeout: 15_000 }).toEqual(['first contact']);
    await send(bob, 'answered');
    await expect.poll(() => bubbleTexts(alice), { timeout: 15_000 }).toEqual(['first contact', 'answered']);
  });

  test.afterAll(async () => {
    await closeAll(alice, bob);
  });

  test('compares codes and marks the key verified', async () => {
    const bobDialog = await openSafetyDialog(bob.page);
    const bobCode = (await bobDialog.locator('.safety-copy-code').getAttribute('data-code')) ?? '';
    expect(bobCode.length).toBeGreaterThan(40);
    const bobNumber = (await bobDialog.locator('#safety-number').innerText()).trim();
    await bob.page.keyboard.press('Escape');
    await expect(bobDialog).toHaveCount(0);

    const dialog = await openSafetyDialog(alice.page);
    await expect(dialog.locator('#safety-title')).toHaveText(`Safety number with @${bob.handle}`);
    await expect(dialog.locator('#safety-their-code')).toBeFocused();
    expect((await dialog.locator('#safety-number').innerText()).trim()).toBe(bobNumber);
    expect(bobNumber.replace(/\s/g, '')).toMatch(/^\d{60}$/);
    await expect(dialog).not.toContainText('You have verified this key.');

    await dialog.locator('#safety-their-code').fill('not their code');
    await dialog.locator('button', { hasText: 'Compare code' }).click();
    await expect(dialog.locator('.dialog-error')).toHaveText('The codes do not match. Do not trust this key.');
    await dialog.locator('#safety-their-code').fill(bobCode);
    await dialog.locator('button', { hasText: 'Compare code' }).click();
    await expect(dialog).toHaveCount(0);
    await expect(toast(alice, `@${bob.handle} verified`)).toBeVisible();

    const again = await openSafetyDialog(alice.page);
    await expect(again).toContainText('You have verified this key.');
    await again.locator('button', { hasText: 'Cancel' }).click();
    await expect(again).toHaveCount(0);
    expectNoErrors(alice, bob);
  });

  // The verification code goes to the clipboard. A browser that refuses
  // the clipboard, or has no clipboard API, gets the code in a read-only
  // field in the dialog, selected, in the body font, to copy by hand.
  test('a refused or missing clipboard shows the code to copy by hand', async () => {
    const page = alice.page;
    const setClipboard = (mode: 'works' | 'refuses' | 'missing') =>
      page.evaluate((mode) => {
        const copied: string[] = ((window as unknown as { copied: string[] }).copied = []);
        const value =
          mode === 'missing'
            ? undefined
            : {
                writeText: (text: string) => {
                  if (mode === 'refuses') return Promise.reject(new DOMException('Write permission denied.', 'NotAllowedError'));
                  copied.push(text);
                  return Promise.resolve();
                },
              };
        Object.defineProperty(navigator, 'clipboard', { configurable: true, value });
      }, mode);
    const close = async (dialog: Awaited<ReturnType<typeof openSafetyDialog>>) => {
      await page.keyboard.press('Escape');
      await expect(dialog).toHaveCount(0);
    };

    await setClipboard('works');
    let dialog = await openSafetyDialog(page);
    const code = (await dialog.locator('.safety-copy-code').getAttribute('data-code')) ?? '';
    expect(code.length).toBeGreaterThan(40);
    await dialog.locator('.safety-copy-code').click();
    await expect(toast(alice, 'Verification code copied')).toBeVisible();
    expect(await page.evaluate(() => (window as unknown as { copied: string[] }).copied)).toEqual([code]);
    await expect(dialog.locator('#safety-my-code')).toBeHidden();
    await close(dialog);

    for (const mode of ['refuses', 'missing'] as const) {
      await setClipboard(mode);
      dialog = await openSafetyDialog(page);
      await expect(dialog.locator('#safety-my-code')).toBeHidden();
      await dialog.locator('.safety-copy-code').click();
      const field = dialog.locator('#safety-my-code');
      await expect(field, mode).toBeVisible();
      await expect(field).toHaveValue(code);
      await expect(field).toHaveAttribute('readonly', '');
      await expect(field).toBeFocused();
      expect(await field.evaluate((node: HTMLTextAreaElement) => [node.selectionStart, node.selectionEnd])).toEqual([0, code.length]);
      // The whole code shows, no line cut at the field's bottom edge, and
      // still at phone width once the window narrows.
      const whole = (node: HTMLTextAreaElement) => node.scrollHeight <= node.clientHeight;
      expect(await field.evaluate(whole), 'a line of the code is cut off').toBe(true);
      const size = page.viewportSize();
      await page.setViewportSize({ width: 360, height: 640 });
      await expect.poll(() => field.evaluate(whole), 'a line of the code is cut off at 360 px').toBe(true);
      if (size) await page.setViewportSize(size);
      const fonts = await field.evaluate((node) => [getComputedStyle(node).fontFamily, getComputedStyle(document.body).fontFamily]);
      expect(fonts[0], 'the body font, not the monospace one').toBe(fonts[1]);
      await expect(dialog.getByLabel('Your verification code')).toHaveValue(code);
      await expect(dialog.locator('#safety-my-code-hint')).toHaveText(
        "This browser didn't let the page copy. Select the code and copy it yourself.",
      );
      await expect(toast(alice, 'Verification code copied')).toHaveCount(0);
      await close(dialog);
    }
    expectNoErrors(alice, bob);
  });

  test('a new key of a verified contact is accepted only by comparing it', async () => {
    await relay('/__test/impersonate', { victim: bob.handle, target: alice.handle, text: 'relay as verified bob' });
    const { page } = alice;
    const banner = page.locator('.key-change-banner');
    await expect(banner).toBeVisible({ timeout: 15_000 });
    await expect(banner.locator('.key-change-text')).toHaveText(
      `@${bob.handle}'s safety number changed. You had verified them, so compare the new number before you trust it.`,
    );
    await expect(page.locator('.panel-msgs .msg-row.them').last()).toContainText('Encrypted message (safety number changed)');
    await expect(page.locator('.panel-header .verified-badge')).toBeHidden();
    // Meanwhile Alice goes on writing to the key she verified.
    await expect(page.locator('.panel-input textarea')).toBeEnabled();
    await send(alice, 'still to the verified key');
    await expect.poll(() => bubbleTexts(bob), { timeout: 15_000 }).toContain('still to the verified key');

    await banner.locator('button', { hasText: 'Compare safety number' }).click();
    const dialog = page.locator('#safety-dialog');
    await expect(dialog).toContainText('This is a new key that has not been accepted yet. Only verify it after comparing it with them.');
    await dialog.locator('button', { hasText: 'Mark as verified' }).click();
    await expect(dialog).toHaveCount(0);
    await expect(banner).toHaveCount(0);
    await expect.poll(() => bubbleTexts(alice), { timeout: 15_000 })
      .toEqual(['first contact', 'answered', 'relay as verified bob', 'still to the verified key']);
    await expect(page.locator('.panel-input textarea')).toBeEnabled();
    expectNoErrors(alice, bob);
  });
});

test.describe('a contact never verified', () => {
  const id = stamp();
  let carol: Device;
  let dave: Device;

  test.beforeAll(async ({ browser }) => {
    await relay('/__test/reset');
    carol = await register(browser, `tcarol${id}`);
    dave = await register(browser, `tdave${id}`);
    await startChat(carol, dave);
    await send(carol, 'hello dave');
    await expect.poll(() => bubbleTexts(dave), { timeout: 15_000 }).toEqual(['hello dave']);
    await send(dave, 'hello carol');
    await expect.poll(() => bubbleTexts(carol), { timeout: 15_000 }).toEqual(['hello dave', 'hello carol']);
  });

  test.afterAll(async () => {
    await closeAll(carol, dave);
  });

  test('declining a swapped key keeps it locked and the chat sending', async () => {
    await relay('/__test/impersonate', { victim: dave.handle, target: carol.handle, text: 'relay try one' });
    const { page } = carol;
    const banner = page.locator('.key-change-banner');
    await expect(banner).toBeVisible({ timeout: 15_000 });
    await expect(banner.locator('.key-change-text')).toHaveText(
      `@${dave.handle}'s safety number changed. Messages from the new key stay locked until you review it.`,
    );
    await expect(page.locator('.conv-item', { hasText: `@${dave.handle}` }).locator('.conv-preview')).toHaveText('Safety number changed');
    await expect(page.locator('.panel-input textarea')).toBeEnabled();
    await send(carol, 'while the banner shows');
    await expect.poll(() => bubbleTexts(dave), { timeout: 15_000 }).toContain('while the banner shows');

    await banner.locator('.key-change-decline').click();
    await expect(page.locator('#confirm-title')).toHaveText(`Decline this key for @${dave.handle}?`);
    await page.click('#confirm-cancel');
    await expect(banner).toBeVisible();
    await banner.locator('.key-change-decline').click();
    await page.click('#confirm-ok');
    await expect(banner).toHaveCount(0);
    await expect(page.locator('.panel-msgs .msg-row.them').last()).toContainText('Encrypted message');
    await send(carol, 'still talking to dave');
    await expect.poll(() => bubbleTexts(dave), { timeout: 15_000 }).toContain('still talking to dave');
    expectNoErrors(carol, dave);
  });

  test('accepting a swapped key opens what it sent', async () => {
    await relay('/__test/impersonate', { victim: dave.handle, target: carol.handle, text: 'relay try two' });
    const { page } = carol;
    const banner = page.locator('.key-change-banner');
    await expect(banner).toBeVisible({ timeout: 15_000 });
    await banner.locator('button', { hasText: 'Review' }).click();
    await expect(page.locator('#confirm-title')).toHaveText(`Accept @${dave.handle}'s new key?`);
    await expect(page.locator('#confirm-ok')).toHaveText('Accept new key');
    await page.click('#confirm-ok');
    await expect(banner).toHaveCount(0);
    await expect.poll(() => bubbleTexts(carol), { timeout: 15_000 }).toContain('relay try two');
    expect(await bubbleTexts(carol)).not.toContain('relay try one');
    await expect(page.locator('.panel-input textarea')).toBeEnabled();
    expectNoErrors(carol, dave);
  });
});
