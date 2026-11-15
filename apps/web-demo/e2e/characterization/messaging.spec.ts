import { expect, test } from '@playwright/test';

import {
  bubbleTexts,
  chooseAction,
  closeAll,
  expectNoErrors,
  openChatWith,
  register,
  relay,
  relayState,
  reload,
  rowOf,
  send,
  sendAll,
  stamp,
  startChat,
  toast,
  type Device,
} from './support';

// A direct conversation in polling mode (the relay's realtime gateway is
// off): starting it, text both ways, replies, reactions, edits, deletes,
// search, forwarding, tabs, history paging and deleting history locally.

test.describe.configure({ mode: 'serial' });

test.describe('a direct conversation', () => {
  const id = stamp();
  let alice: Device;
  let bob: Device;
  let carol: Device;

  test.beforeAll(async ({ browser }) => {
    await relay('/__test/reset');
    alice = await register(browser, `alice${id}`);
    bob = await register(browser, `bob${id}`);
    carol = await register(browser, `carol${id}`);
  });

  test.afterAll(async () => {
    await closeAll(alice, bob, carol);
  });

  test('the new chat dialog checks the handle and opens the conversation', async () => {
    const { page } = alice;
    await page.click('#new-chat-btn');
    await expect(page.locator('#new-chat-dialog')).toBeVisible();
    await expect(page.locator('#new-peer-input')).toBeFocused();
    await page.click('#new-confirm');
    await expect(page.locator('#new-peer-error')).toHaveText('Enter a handle');
    await page.fill('#new-peer-input', alice.handle);
    await page.click('#new-confirm');
    await expect(page.locator('#new-peer-error')).toHaveText("You can't chat with yourself");
    await page.fill('#new-peer-input', `nobody${id}`);
    await page.press('#new-peer-input', 'Enter');
    await expect(page.locator('#new-peer-error')).toHaveText('User not found');
    await page.click('#new-cancel');
    await expect(page.locator('#new-chat-dialog')).toBeHidden();

    await startChat(alice, bob);
    await expect(page.locator('#tab-strip .tab')).toHaveText([`@${bob.handle}`]);
    await expect(page.locator('.panel .panel-msgs .empty-title')).toHaveText('No messages yet');
    await expect(page.locator('.panel-input textarea')).toHaveAttribute('placeholder', 'Message');
    await expect(page.locator('.panel-input > *')).toHaveCount(5);
    await expect(page.locator('.panel-input .file-btn')).toHaveAttribute('aria-label', 'Attach a file');
    await expect(page.locator('.panel-input .image-btn:not(.file-btn)')).toHaveAttribute('aria-label', 'Attach an image');
    await expect(page.locator('.panel-header .mute-toggle')).toHaveAttribute('aria-pressed', 'false');
    await expect(bob.page.locator('.conv-item', { hasText: `@${alice.handle}` })).toContainText('No messages yet');
    expectNoErrors(alice, bob);
  });

  test('text goes both ways, with previews, groups and statuses', async () => {
    await send(alice, 'hello bob');
    await expect.poll(() => bubbleTexts(bob), { timeout: 15_000 }).toEqual(['hello bob']);
    await expect(bob.page.locator('.panel-msgs .group-meta')).toHaveText([`@${alice.handle}`]);
    await expect(alice.page.locator('.msg-group.me .msg-status')).toHaveAttribute('title', 'Sent');
    await expect(alice.page.locator('.msg-group.me .msg-status use')).toHaveAttribute('href', '#i-check');

    await send(bob, 'hi *alice* and `code`', 'hi alice and code');
    await expect.poll(() => bubbleTexts(alice), { timeout: 15_000 }).toEqual(['hello bob', 'hi alice and code']);
    await expect(alice.page.locator('.msg-row.them .msg-text strong')).toHaveText('alice');
    await expect(alice.page.locator('.msg-row.them .msg-text code')).toHaveText('code');
    await expect(alice.page.locator('.conv-item', { hasText: `@${bob.handle}` }).locator('.conv-preview'))
      .toHaveText('hi *alice* and `code`');
    await expect(alice.page.locator('.panel .day-divider')).toHaveCount(1);
    expectNoErrors(alice, bob);
  });

  test('a reply quotes the message it answers', async () => {
    await expect(async () => {
      await rowOf(bob, 'hello bob').hover();
      await rowOf(bob, 'hello bob').locator('.msg-reply-btn').click({ timeout: 2_000 });
      await expect(bob.page.locator('.reply-banner')).toBeVisible({ timeout: 1_000 });
    }).toPass({ timeout: 20_000 });
    await expect(bob.page.locator('.reply-banner-meta')).toHaveText(`Reply to @${alice.handle}`);
    await expect(bob.page.locator('.reply-banner-snippet')).toHaveText('hello bob');
    await send(bob, 'replying to you');
    await expect(bob.page.locator('.reply-banner')).toHaveCount(0);
    await expect(rowOf(bob, 'replying to you').locator('.msg-reply-head')).toHaveText('hello bob');
    await expect(rowOf(alice, 'replying to you').locator('.msg-reply-head')).toHaveText('hello bob', { timeout: 15_000 });
    expectNoErrors(alice, bob);
  });

  test('a reaction shows on both sides and is taken back', async () => {
    await expect(async () => {
      await rowOf(bob, 'hello bob').click({ button: 'right' });
      await bob.page.locator('.msg-action-menu .msg-action-row button').first().click({ timeout: 2_000 });
    }).toPass({ timeout: 20_000 });
    const mine = rowOf(bob, 'hello bob').locator('.msg-reaction-chip');
    await expect(mine).toHaveText('👍 1');
    await expect(mine).toHaveClass(/mine/);
    await expect(mine).toHaveAttribute('title', 'Your reaction. Click to remove it');
    const theirs = rowOf(alice, 'hello bob').locator('.msg-reaction-chip');
    await expect(theirs).toHaveText('👍 1', { timeout: 15_000 });
    await expect(theirs).not.toHaveClass(/mine/);
    await expect(alice.page.locator('.panel-msgs')).not.toContainText('Reaction');

    await expect(async () => {
      await rowOf(bob, 'hello bob').locator('.msg-reaction-chip').click({ timeout: 2_000 });
      await expect(rowOf(bob, 'hello bob').locator('.msg-reaction-chip')).toHaveCount(0, { timeout: 2_000 });
    }).toPass({ timeout: 20_000 });
    await expect(rowOf(alice, 'hello bob').locator('.msg-reaction-chip')).toHaveCount(0, { timeout: 15_000 });
    expectNoErrors(alice, bob);
  });

  test('the action menu offers what fits the message', async () => {
    await rowOf(alice, 'hello bob').click({ button: 'right' });
    const own = alice.page.locator('.msg-action-menu');
    await expect(own.locator('.msg-action-row button')).toHaveText(['👍', '❤️', '😂', '😢', '🔥', '🎉']);
    await expect(own.locator('.msg-action-item').first()).toHaveText('Reply');
    await expect(own.locator('.msg-action-item', { hasText: 'Edit' })).toHaveText('Edit');
    await expect(own.locator('.msg-action-item.danger', { hasText: 'Delete' })).toHaveText('Delete');
    await alice.page.locator('#sidebar-me').click();
    await expect(own).toHaveCount(0);

    await rowOf(alice, 'replying to you').click({ button: 'right' });
    const peers = alice.page.locator('.msg-action-menu');
    await expect(peers.locator('.msg-action-item', { hasText: 'Copy' })).toHaveText('Copy');
    await expect(peers.locator('.msg-action-item', { hasText: 'Edit' })).toHaveCount(0);
    await alice.page.keyboard.press('Escape');
    await alice.page.locator('#sidebar-me').click();
    expectNoErrors(alice, bob);
  });

  // Added with the split, which fixed this: the monolith added these items
  // to an open menu from the row right-clicked before, so the first
  // right-click had none and a report could name the previous message.
  test('a peer message offers forward, block and report about itself on the first right-click', async () => {
    const { page } = alice;
    const row = rowOf(alice, 'replying to you');
    const messageId = await row.getAttribute('data-msg-id');
    // Every menu that opens is kept, so what it offered can be read even
    // after a redraw (which scrolls the panel) has closed it.
    await page.evaluate(() => {
      const opened: Element[] = [];
      Object.defineProperty(window, '__openedMenus', { value: opened });
      new MutationObserver((records) => {
        for (const record of records) {
          for (const node of record.addedNodes) if ((node as Element).classList?.contains('msg-action-menu')) opened.push(node as Element);
        }
      }).observe(document.body, { childList: true });
    });
    await rowOf(alice, 'hello bob').click({ button: 'right' });
    await page.locator('#sidebar-me').click();
    await row.click({ button: 'right' });
    await expect.poll(() => page.evaluate(() => (window as unknown as { __openedMenus: Element[] }).__openedMenus.length)).toBe(2);
    expect(await page.evaluate(() => {
      const [, menu] = (window as unknown as { __openedMenus: Element[] }).__openedMenus;
      return [...menu.querySelectorAll('.msg-action-item')].map((item) => item.textContent);
    })).toEqual(['Reply', 'Copy', 'Forward', 'Block', 'Report']);

    const menu = page.locator('.msg-action-menu');
    await expect(async () => {
      if (!(await menu.isVisible())) await row.click({ button: 'right' });
      await menu.locator('.msg-action-item', { hasText: 'Report' }).click({ timeout: 1_000 });
    }).toPass({ timeout: 20_000 });
    await page.locator('#report-dialog input[value="harassment"]').check();
    await page.locator('#report-submit').click();
    await expect(toast(alice, 'Report sent')).toBeVisible();
    type Report = { reportedHandle: string; body: { messageId: string; reason: string } };
    const reports = await relayState<Report[]>('/__test/reports');
    expect(reports.at(-1)).toMatchObject({ reportedHandle: bob.handle, body: { messageId, reason: 'harassment' } });
    expectNoErrors(alice, bob);
  });

  test('an edit replaces the text on both sides', async () => {
    await alice.page.evaluate(() => {
      window.prompt = () => 'hello bob, edited';
    });
    await chooseAction(alice, 'hello bob', 'Edit');
    await expect(rowOf(alice, 'hello bob, edited').locator('.msg-edited')).toHaveText('(edited)');
    await expect(rowOf(bob, 'hello bob, edited').locator('.msg-edited')).toHaveText('(edited)', { timeout: 15_000 });
    expectNoErrors(alice, bob);
  });

  test('a delete leaves a tombstone on both sides and offers to undo', async () => {
    await send(alice, 'regretted words');
    await expect.poll(() => bubbleTexts(bob), { timeout: 15_000 }).toContain('regretted words');
    await chooseAction(alice, 'regretted words', 'Delete');
    await expect(alice.page.locator('#confirm-title')).toHaveText('Delete message');
    await alice.page.click('#confirm-ok');
    const undo = toast(alice, 'Message deleted');
    await expect(undo).toBeVisible();
    await undo.locator('button', { hasText: 'Undo' }).click();
    await expect(alice.page.locator('.panel-input textarea')).toHaveValue('regretted words');
    await expect(toast(alice, 'Put back in the message box. Press Enter to send it again')).toBeVisible();
    for (const device of [alice, bob]) {
      await expect.poll(() => bubbleTexts(device), { timeout: 15_000 }).toContain('Message deleted');
      expect(await bubbleTexts(device)).not.toContain('regretted words');
    }
    await alice.page.evaluate(() => {
      const textarea = document.querySelector('.panel-input textarea') as HTMLTextAreaElement;
      textarea.value = '';
      textarea.dispatchEvent(new Event('input', { bubbles: true }));
    });
    expectNoErrors(alice, bob);
  });

  test('search in the conversation counts and marks matches', async () => {
    const { page } = alice;
    await page.locator('.panel-header button[aria-label^="Find in chat"]').click();
    const search = page.locator('.panel-search input');
    await expect(search).toBeFocused();
    await search.fill('bob');
    await expect(page.locator('.panel-search .count')).toHaveText('1/1');
    await expect(rowOf(alice, 'hello bob, edited')).toHaveClass(/search-active/);
    await expect(rowOf(alice, 'hello bob, edited').locator('mark')).toHaveText('bob');
    await search.fill('nothing like this');
    await expect(page.locator('.panel-search .count')).toHaveText('0/0');
    await search.press('Escape');
    await expect(page.locator('.panel-search')).toHaveCount(0);
    expectNoErrors(alice);
  });

  test('peer messages a panel shows are marked read', async () => {
    const reads: Array<{ url: string; body: unknown }> = [];
    bob.page.on('request', (request) => {
      if (request.method() === 'POST' && /\/v1\/messages\/[^/]+\/read$/.test(request.url())) {
        reads.push({ url: new URL(request.url()).pathname, body: request.postDataJSON() });
      }
    });
    await send(alice, 'please read this');
    await expect(rowOf(bob, 'please read this')).toHaveCount(1, { timeout: 15_000 });
    const messageId = await rowOf(bob, 'please read this').getAttribute('data-msg-id');
    await expect.poll(() => reads, { timeout: 10_000 }).toEqual([{ url: `/v1/messages/${messageId}/read`, body: {} }]);
    expectNoErrors(alice, bob);
  });

  test('a text is forwarded to another conversation', async () => {
    await startChat(alice, carol);
    await openChatWith(alice, bob);
    await chooseAction(alice, 'replying to you', 'Forward');
    const dialog = alice.page.locator('.dialog', { hasText: 'Forward message' });
    await expect(dialog.locator('.forward-list-item')).toHaveCount(1);
    await expect(dialog.locator('.forward-list-item')).toContainText(`@${carol.handle}`);
    await expect(dialog.locator('#fwd-confirm')).toBeDisabled();
    await dialog.locator('.forward-list-item').click();
    await dialog.locator('#fwd-confirm').click();
    await expect(toast(alice, 'Forwarded')).toBeVisible();
    await expect.poll(() => bubbleTexts(carol), { timeout: 15_000 }).toEqual(['replying to you']);
    expectNoErrors(alice, carol);
  });

  test('tabs switch, split and close', async () => {
    const { page } = alice;
    await expect(page.locator('#tab-strip .tab')).toHaveText([`@${bob.handle}`, `@${carol.handle}`]);
    await expect(page.locator('#tab-strip .tab.active')).toHaveText(`@${bob.handle}`);
    await page.click('#split-btn');
    await expect(page.locator('#split-btn')).toHaveClass(/active/);
    await expect(page.locator('#panels .panel .panel-title .name')).toHaveText([`@${bob.handle}`, `@${carol.handle}`]);
    await expect(page.locator('#tab-strip .tab.secondary')).toHaveText(`@${carol.handle}`);
    await page.click('#split-btn');
    await expect(page.locator('#panels .panel')).toHaveCount(1);
    await page.locator('#tab-strip .tab', { hasText: carol.handle }).click();
    await expect(page.locator('.panel .panel-title .name')).toHaveText(`@${carol.handle}`);
    await page.locator('#tab-strip .tab', { hasText: carol.handle }).locator('.tab-close').click();
    await expect(page.locator('#tab-strip .tab')).toHaveText([`@${bob.handle}`]);
    await expect(page.locator('.panel .panel-title .name')).toHaveText(`@${bob.handle}`);
    expectNoErrors(alice);
  });

  test('history longer than a page comes back after a reload', async () => {
    const backlog = Array.from({ length: 60 }, (_, i) => `page ${String(i).padStart(2, '0')}`);
    await sendAll(alice, backlog);
    await expect(alice.page.locator('.msg-row.me:not(:has(.msg.pending))')).toHaveCount(backlog.length + 3, { timeout: 30_000 });
    const expected = ['hello bob, edited', 'hi alice and code', 'replying to you', 'Message deleted', 'please read this', ...backlog];
    await expect.poll(() => bubbleTexts(bob), { timeout: 30_000 }).toEqual(expected);
    for (const device of [bob, alice]) {
      await reload(device);
      await openChatWith(device, device === bob ? alice : bob);
      await expect.poll(() => bubbleTexts(device), { timeout: 30_000 }).toEqual(expected);
    }
    await expect(bob.page.locator('.panel-msgs')).not.toContainText('Encrypted message');
    expectNoErrors(alice, bob);
  });

  test('deleting history on this device empties the conversation for good', async () => {
    const { page } = bob;
    await page.locator('.panel-header button[aria-label="Delete history on this device"]').click();
    await expect(page.locator('#confirm-title')).toHaveText('Delete history on this device');
    await page.click('#confirm-ok');
    await expect(page.locator('.panel .panel-msgs .empty-title')).toHaveText('No messages yet');
    await expect(page.locator('.conv-item', { hasText: `@${alice.handle}` }).locator('.conv-preview')).toHaveText('No messages yet');
    await page.waitForTimeout(5_000);
    expect(await bubbleTexts(bob)).toEqual([]);
    await send(alice, 'after the purge');
    await expect.poll(() => bubbleTexts(bob), { timeout: 15_000 }).toEqual(['after the purge']);
    expectNoErrors(alice, bob);
  });
});
