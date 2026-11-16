import { expect, test } from '@playwright/test';

import {
  bubbleTexts,
  chooseAction,
  closeAll,
  expectNoErrors,
  openMenuItem,
  register,
  relay,
  rowOf,
  send,
  stamp,
  startChat,
  toast,
  type Device,
} from './support';

// Blocking from a message, and what Settings lists: a block cuts the direct
// conversation off at the relay (a send is refused), Settings lists the
// blocked account until it is unblocked, and the list says when it is empty
// and when it could not be loaded, in the words of the Settings label.

test.describe.configure({ mode: 'serial' });

test.describe('blocking', () => {
  const id = stamp();
  let alice: Device;
  let bob: Device;

  test.beforeAll(async ({ browser }) => {
    await relay('/__test/reset');
    alice = await register(browser, `alice${id}`);
    bob = await register(browser, `bob${id}`);
    await startChat(alice, bob);
    await send(bob, 'hi alice');
    await expect.poll(() => bubbleTexts(alice), { timeout: 15_000 }).toContain('hi alice');
  });

  test.afterAll(async () => {
    await closeAll(alice, bob);
  });

  test('with nobody blocked, Settings says so', async () => {
    await openMenuItem(alice, 'open-settings');
    const dialog = alice.page.locator('#settings-dialog');
    await expect(dialog.locator('[data-blocked-section] .settings-label')).toHaveText('Blocked accounts');
    await expect(dialog.locator('.blocked-empty')).toHaveText('No blocked accounts');
    await expect(dialog.locator('.blocked-row')).toHaveCount(0);
    await dialog.locator('#settings-close').click();
    expectNoErrors(alice);
  });

  test('a block refuses their sends, and unblocking from Settings lets the retry through', async () => {
    await chooseAction(alice, 'hi alice', 'Block');
    await expect(alice.page.locator('#confirm-title')).toHaveText(`Block @${bob.handle}?`);
    await alice.page.click('#confirm-ok');
    await expect(toast(alice, `@${bob.handle} blocked`)).toBeVisible();

    await send(bob, 'are you there?');
    await expect(bob.page.locator('.msg-group.me .msg-status.failed')).toHaveCount(1);

    await openMenuItem(alice, 'open-settings');
    const dialog = alice.page.locator('#settings-dialog');
    const row = dialog.locator('.blocked-row');
    await expect(row).toHaveCount(1);
    await expect(row).toContainText(`@${bob.handle}`);
    await expect(dialog.locator('.blocked-empty')).toHaveCount(0);

    await row.locator('.unblock').click();
    await expect(toast(alice, `@${bob.handle} unblocked`)).toBeVisible();
    await expect(dialog.locator('.blocked-row')).toHaveCount(0);
    await expect(dialog.locator('.blocked-empty')).toHaveText('No blocked accounts');
    await dialog.locator('#settings-close').click();

    await bob.page.locator('.msg-group.me .msg-action', { hasText: 'Send again' }).click();
    await expect.poll(() => bubbleTexts(alice), { timeout: 15_000 }).toContain('are you there?');
    await expect(bob.page.locator('.msg-group.me .msg-status.failed')).toHaveCount(0);
    await expect(rowOf(bob, 'are you there?')).toHaveCount(1);
    expectNoErrors(alice, bob);
  });

  test('an unblock the server refuses keeps the row', async () => {
    await chooseAction(alice, 'are you there?', 'Block');
    await alice.page.click('#confirm-ok');
    await expect(toast(alice, `@${bob.handle} blocked`)).toBeVisible();
    await alice.page.route('**/v1/safety/blocks/*', (route) =>
      route.request().method() === 'DELETE'
        ? route.fulfill({ status: 503, json: { code: 'internal_error', message: 'try later' } })
        : route.fallback());

    await openMenuItem(alice, 'open-settings');
    const dialog = alice.page.locator('#settings-dialog');
    await dialog.locator('.blocked-row .unblock').click();
    await expect(toast(alice, 'Could not unblock: try later')).toBeVisible();
    await expect(dialog.locator('.blocked-row')).toHaveCount(1);
    await expect(dialog.locator('.blocked-empty')).toHaveCount(0);
    await dialog.locator('#settings-close').click();
    await alice.page.unroute('**/v1/safety/blocks/*');
    expectNoErrors(alice);
  });

  // With the focus on the page (a click on the dialog's text), Esc still
  // closes the report dialog for good, so it opens again.
  test('the report dialog closes on Esc from outside it, and opens again', async () => {
    const { page } = alice;
    const dialog = page.locator('#report-dialog');
    await chooseAction(alice, 'are you there?', 'Report');
    await expect(dialog).toBeVisible();
    await expect(dialog.locator('.dialog-sub')).toHaveText(
      'The report includes your account, theirs, the reason and which chat and message, but not what it says.',
    );
    await expect(dialog.locator('.choice span')).toHaveText([
      'Spam',
      'Harassment',
      'Pretending to be someone',
      'Child sexual abuse',
      'Violence or threats',
      'Scam or fraud',
      'Something else',
    ]);
    await dialog.locator('#report-title').click();
    await page.keyboard.press('Escape');
    await expect(dialog).toHaveCount(0);

    await chooseAction(alice, 'are you there?', 'Report');
    await expect(dialog).toBeVisible();
    await dialog.locator('button', { hasText: 'Cancel' }).click();
    await expect(dialog).toHaveCount(0);
    expectNoErrors(alice);
  });

  test('a list that could not be loaded is not shown as empty', async () => {
    await alice.page.route('**/v1/safety/blocks', (route) =>
      route.fulfill({ status: 503, json: { code: 'internal_error', message: 'try later' } }));
    await openMenuItem(alice, 'open-settings');
    const dialog = alice.page.locator('#settings-dialog');
    await expect(dialog.locator('.blocked-empty')).toHaveText('Could not load blocked accounts');
    await expect(dialog.locator('.blocked-row')).toHaveCount(0);
    await dialog.locator('#settings-close').click();
    await alice.page.unroute('**/v1/safety/blocks');
    expectNoErrors(alice);
  });
});
