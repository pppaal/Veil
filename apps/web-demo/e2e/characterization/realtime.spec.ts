import { expect, test } from '@playwright/test';

import {
  bubbleTexts,
  closeAll,
  expectNoErrors,
  register,
  relay,
  rowOf,
  send,
  stamp,
  startChat,
  type Device,
} from './support';

// With the relay's realtime gateway on: messages, edits and deletes are
// pushed, a read receipt reaches only the sender, typing shows in the
// peer's header while it lasts, and the connection comes back as soon as
// the browser is online again.

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

  test('the bar says nothing once the push channel is up', async () => {
    for (const device of [alice, bob]) await expect(device.page.locator('#conn-status')).toHaveClass(/connected/, { timeout: 15_000 });
    await expect(alice.page.locator('#conn-status')).toBeHidden();
    await expect(alice.page.locator('.topbar-name')).toHaveText('Chats');
    expectNoErrors(alice, bob);
  });

  test('a message is pushed, read, and its read receipt shows to the sender', async () => {
    await startChat(alice, bob);
    await send(alice, 'are you there');
    await expect.poll(() => bubbleTexts(bob), { timeout: 5_000 }).toEqual(['are you there']);
    const status = alice.page.locator('.msg-group.me .msg-status');
    await expect(status).toHaveAttribute('title', 'Read', { timeout: 10_000 });
    // Two filled check circles; the word is for assistive technology only.
    await expect(status).toHaveText('Read');
    await expect(status.locator('.sr-only')).toHaveText('Read');
    await expect(status.locator('use')).toHaveAttribute('href', '#i-tick-read');
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
    await expect(sub).toHaveText('typing…', { timeout: 5_000 });
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
    const messageId = await rowOf(alice, 'are you there').getAttribute('data-msg-id');
    await rowOf(alice, 'are you there').click({ button: 'right' });
    await alice.page.locator('.msg-action-menu .msg-action-item', { hasText: 'Edit' }).click();
    // The edit happens in the composer: Enter saves it.
    await expect(alice.page.locator('.edit-banner')).toBeVisible();
    await alice.page.evaluate(() => {
      const textarea = document.querySelector('.panel-input textarea') as HTMLTextAreaElement;
      textarea.value = 'are you there, really';
      textarea.dispatchEvent(new Event('input', { bubbles: true }));
      textarea.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true }));
    });
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

  test("typing ends the moment the peer's message shows, with no stop", async () => {
    const sub = alice.page.locator('.panel .panel-title > div:last-child');
    // Bob's typing stops never reach the relay, as when the server drops a
    // stop that follows its start too closely: only the 6 second expiry
    // would end his "typing…" otherwise.
    await bob.page.evaluate(() => {
      const original = WebSocket.prototype.send;
      (window as unknown as { restoreSend: () => void }).restoreSend = () => {
        WebSocket.prototype.send = original;
      };
      WebSocket.prototype.send = function (this: WebSocket, data: string | ArrayBufferLike | Blob | ArrayBufferView) {
        if (typeof data === 'string' && data.includes('"typing.stop"')) return;
        original.call(this, data);
      };
    });
    await bob.page.evaluate(() => {
      const textarea = document.querySelector('.panel-input textarea') as HTMLTextAreaElement;
      textarea.value = 'on my';
      textarea.dispatchEvent(new Event('input', { bubbles: true }));
    });
    await expect(sub).toHaveText('typing…', { timeout: 5_000 });

    // What the header says in the first frame that shows the message.
    const atArrival = alice.page.waitForFunction(() => {
      const texts = [...document.querySelectorAll('.panel-msgs .msg-row .msg-text')].map((node) => node.textContent);
      if (!texts.includes('on my way')) return null;
      return { subtitle: document.querySelector('.panel .panel-title > div:last-child')?.textContent ?? '' };
    }, null, { timeout: 5_000 });
    await send(bob, 'on my way');
    expect(await (await atArrival).jsonValue()).toEqual({ subtitle: '' });
    await expect(sub).toHaveClass('sub');
    await bob.page.evaluate(() => (window as unknown as { restoreSend: () => void }).restoreSend());
    expectNoErrors(alice, bob);
  });

  test('the bar reconnects as soon as the browser is back online', async () => {
    const bar = alice.page.locator('#conn-status');
    // The relay closes every live connection and turns new ones away. A
    // socket the server closed is not retried on its own.
    await relay('/__test/realtime', { enabled: false });
    await expect(bar).toHaveText('Offline', { timeout: 10_000 });
    await relay('/__test/realtime', { enabled: true });
    await alice.page.evaluate(() => window.dispatchEvent(new Event('online')));
    await expect(bar).toHaveClass(/connected/, { timeout: 5_000 });
    await expect(bar).toBeHidden();
    expectNoErrors(alice, bob);
  });
});
