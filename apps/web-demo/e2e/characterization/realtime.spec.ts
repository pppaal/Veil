import { expect, test } from '@playwright/test';

import {
  bubbleTexts,
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

// With the relay's realtime gateway on: messages, edits and deletes are
// pushed, a read receipt reaches only the sender, and typing shows in the
// peer's header while it lasts.

test.describe.configure({ mode: 'serial' });

test.describe('realtime', () => {
  const id = stamp();
  let alice: Device;
  let bob: Device;

  test.beforeAll(async ({ browser }) => {
    await relay('/__test/reset');
    await relay('/__test/realtime', { enabled: true });
    alice = await register(browser, `ralice${id}`);
    bob = await register(browser, `rbob${id}`);
  });

  test.afterAll(async () => {
    await relay('/__test/realtime', { enabled: false });
    await closeAll(alice, bob);
  });

  test('the bar says nothing once the push channel is up, and the menu reports it', async () => {
    for (const device of [alice, bob]) await expect(device.page.locator('#conn-status')).toHaveClass(/connected/, { timeout: 15_000 });
    await expect(alice.page.locator('#conn-status')).toBeHidden();
    await openMenuItem(alice, 'ws-info');
    await expect(toast(alice, 'Connection: live (WebSocket)')).toBeVisible();
    expectNoErrors(alice, bob);
  });

  test('a message is pushed, read, and its read receipt shows to the sender', async () => {
    await startChat(alice, bob);
    await send(alice, 'are you there');
    await expect.poll(() => bubbleTexts(bob), { timeout: 5_000 }).toEqual(['are you there']);
    const status = alice.page.locator('.msg-group.me .msg-status');
    await expect(status).toHaveAttribute('title', 'Read', { timeout: 10_000 });
    await expect(status).toHaveText('Read');
    await expect(status).toHaveClass(/read/);
    expectNoErrors(alice, bob);
  });

  test('typing shows in the peer header until it stops', async () => {
    const sub = alice.page.locator('.panel .panel-title > div:last-child');
    await expect(sub).toHaveText('');
    await bob.page.evaluate(() => {
      const textarea = document.querySelector('.panel-input textarea') as HTMLTextAreaElement;
      textarea.value = 'typ';
      textarea.dispatchEvent(new Event('input', { bubbles: true }));
    });
    await expect(sub).toHaveText('Typing…', { timeout: 5_000 });
    await expect(sub).toHaveClass('sub typing');
    // The stop goes out once the composer has been idle for four seconds.
    await expect(sub).toHaveText('', { timeout: 10_000 });
    await expect(sub).toHaveClass('sub');
    await bob.page.evaluate(() => {
      const textarea = document.querySelector('.panel-input textarea') as HTMLTextAreaElement;
      textarea.value = '';
      textarea.dispatchEvent(new Event('input', { bubbles: true }));
    });
    expectNoErrors(alice, bob);
  });

  test('edits and deletes are pushed to the peer', async () => {
    await alice.page.evaluate(() => {
      window.prompt = () => 'are you there, really';
    });
    const messageId = await rowOf(alice, 'are you there').getAttribute('data-msg-id');
    await rowOf(alice, 'are you there').click({ button: 'right' });
    await alice.page.locator('.msg-action-menu .msg-action-item', { hasText: 'Edit' }).click();
    await expect(rowOf(bob, 'are you there, really').locator('.msg-edited')).toHaveText('(edited)', { timeout: 5_000 });
    // The edit's push reaches the sender too, and it must not put the old
    // text back on the sender's own bubble.
    const own = alice.page.locator(`.panel-msgs .msg-row[data-msg-id="${messageId}"]`);
    await expect(own.locator('.msg-edited')).toHaveText('(edited)', { timeout: 5_000 });
    await expect(own.locator('.msg-text')).toHaveText('are you there, really');
    await alice.page.locator(`.panel-msgs .msg-row[data-msg-id="${messageId}"]`).click({ button: 'right' });
    await alice.page.locator('.msg-action-menu .msg-action-item.danger').click();
    await alice.page.click('#confirm-ok');
    for (const device of [alice, bob]) {
      await expect.poll(() => bubbleTexts(device), { timeout: 5_000 }).toEqual(['Message deleted']);
    }
    expectNoErrors(alice, bob);
  });
});
