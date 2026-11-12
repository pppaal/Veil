import { expect, test } from '@playwright/test';

import { bubbleTexts, closeAll, expectNoErrors, register, relay, reopen, rowOf, send, stamp, startChat, toast, type Device } from './support';

// What happens to a send the relay does not take at once: refused, it waits
// with its bubble for Retry, which sends the very envelope that was sealed;
// in flight when the tab dies, it is in the outbound queue already and goes
// out from the next page.

test.describe.configure({ mode: 'serial' });

test.describe('a send the relay does not take at once', () => {
  const id = stamp();
  let alice: Device;
  let bob: Device;

  test.beforeAll(async ({ browser }) => {
    await relay('/__test/reset');
    alice = await register(browser, `dalice${id}`);
    bob = await register(browser, `dbob${id}`);
    await startChat(alice, bob);
    await send(alice, 'first');
    await expect.poll(() => bubbleTexts(bob), { timeout: 15_000 }).toEqual(['first']);
  });

  test.afterAll(async () => {
    await closeAll(alice, bob);
  });

  test('refused once, it goes out on retry', async () => {
    const { page } = alice;
    let refusals = 1;
    await page.route('**/v1/messages', async (route) => {
      if (route.request().method() === 'POST' && refusals > 0) {
        refusals -= 1;
        await route.fulfill({ status: 400, json: { code: 'bad_request', message: 'refused once' } });
        return;
      }
      await route.fallback();
    });
    await send(alice, 'refused, then retried');
    const failed = rowOf(alice, 'refused, then retried');
    await expect(page.locator('.msg-group.me .msg-status.failed')).toHaveCount(1);
    await expect(toast(alice, 'refused once')).toBeVisible();

    await page.locator('.msg-group.me .msg-action', { hasText: '다시 보내기' }).click();
    await expect.poll(() => bubbleTexts(bob), { timeout: 15_000 }).toEqual(['first', 'refused, then retried']);
    await expect(failed).toHaveCount(1);
    await expect(page.locator('.msg-group.me .msg-status.failed')).toHaveCount(0);
    await expect(page.locator('.msg-group.me .msg-status.pending')).toHaveCount(0);
    await page.unroute('**/v1/messages');
    expectNoErrors(alice, bob);
  });

  test('in flight when the tab dies, it goes out from the next page', async () => {
    const stalled: string[] = [];
    await alice.page.route('**/v1/messages', async (route) => {
      if (route.request().method() !== 'POST') return route.fallback();
      // The request never gets an answer: the tab goes away first.
      stalled.push(route.request().postDataJSON().clientMessageId);
    });
    await alice.page.evaluate((body) => {
      const textarea = document.querySelector('.panel-input textarea') as HTMLTextAreaElement;
      textarea.value = body;
      textarea.dispatchEvent(new Event('input', { bubbles: true }));
      textarea.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true }));
    }, 'sent as the tab died');
    await expect.poll(() => stalled.length).toBe(1);
    // The tab is gone with the request in flight: frozen, no code of it runs
    // again (a closed page could still run the request's failure handler).
    const dead = alice.page;
    const devtools = await alice.context.newCDPSession(dead);
    await devtools.send('Page.setWebLifecycleState', { state: 'frozen' });

    await reopen(alice);
    await expect(alice.page.locator('#app')).toBeVisible();
    await expect.poll(() => bubbleTexts(bob), { timeout: 30_000 })
      .toEqual(['first', 'refused, then retried', 'sent as the tab died']);
    expect(stalled).toHaveLength(1);
    await dead.close();
    expectNoErrors(alice, bob);
  });
});
