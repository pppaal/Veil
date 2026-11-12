import { expect, test, type Page } from '@playwright/test';

import {
  bubbleTexts,
  closeAll,
  expectNoErrors,
  openChatWith,
  register,
  relay,
  reload,
  rowOf,
  send,
  stamp,
  startChat,
  type Device,
} from './support';

// What a relay that rewrites its lists can and cannot change. It serves the
// conversation list and each history; the frames in them authenticate, but
// the lists around them do not. A history holds only its own conversation's
// messages, a direct conversation keeps the peer it was bound to, a
// conversation is shown under the peer its crypto is about whatever the list
// calls our own entry in it, and a handle shown for another account than the
// one this device knows under it, our own handle shown for another account,
// or one no honest server issues (a lookalike of a known one), is held until
// the user chooses to talk to that account.

test.describe.configure({ mode: 'serial' });

interface Member {
  userId: string;
  handle: string;
}
interface Summary {
  id: string;
  members: Member[];
}

// Rewrites every answer to GET /v1/conversations on this page.
async function rewriteList(page: Page, rewrite: (items: Summary[]) => void): Promise<void> {
  await page.route('**/v1/conversations', async (route) => {
    const response = await route.fetch();
    const body = await response.json();
    rewrite(body.items ?? body);
    await route.fulfill({ response, json: body });
  });
}

const conversationOf = (items: Summary[], handle: string) =>
  items.find((conv) => conv.members.some((member) => member.handle === handle));

test.describe('a relay that rewrites its lists', () => {
  const id = stamp();
  let alice: Device;
  let bob: Device;
  let carol: Device;

  test.beforeAll(async ({ browser }) => {
    await relay('/__test/reset');
    alice = await register(browser, `lalice${id}`);
    bob = await register(browser, `lbob${id}`);
    carol = await register(browser, `lcarol${id}`);
    await startChat(alice, bob);
    await send(bob, 'bob says the code is 4471');
    await expect(rowOf(alice, 'bob says the code is 4471')).toHaveCount(1, { timeout: 15_000 });
    await send(alice, 'thanks bob');
    await startChat(alice, carol);
    await send(carol, 'hi from carol');
    await expect(rowOf(alice, 'hi from carol')).toHaveCount(1, { timeout: 15_000 });
  });

  test.afterAll(async () => {
    await closeAll(alice, bob, carol);
  });

  test("a history holds none of another conversation's messages", async () => {
    const { page } = alice;
    // Carol's history comes back with Bob's messages, unchanged, in front.
    let bobConversation = '';
    let carolConversation = '';
    let bobItems: unknown[] = [];
    await rewriteList(page, (items) => {
      bobConversation = conversationOf(items, bob.handle)?.id ?? bobConversation;
      carolConversation = conversationOf(items, carol.handle)?.id ?? carolConversation;
    });
    await page.route('**/v1/conversations/*/messages?*', async (route) => {
      const response = await route.fetch();
      const body = await response.json();
      const { pathname } = new URL(route.request().url());
      if (pathname.includes(bobConversation)) bobItems = body.items;
      else if (pathname.includes(carolConversation)) body.items = [...bobItems, ...body.items];
      await route.fulfill({ response, json: body });
    });
    await reload(alice);
    await openChatWith(alice, bob);
    await expect.poll(() => bubbleTexts(alice), { timeout: 15_000 }).toEqual(['bob says the code is 4471', 'thanks bob']);
    await openChatWith(alice, carol);
    await expect.poll(() => bubbleTexts(alice), { timeout: 15_000 }).toEqual(['hi from carol']);
    // Let a polling round fetch both histories again.
    await page.waitForTimeout(5_000);
    expect(bobItems).toHaveLength(2);
    expect(await bubbleTexts(alice)).toEqual(['hi from carol']);
    await page.unroute('**/v1/conversations/*/messages?*');
    await page.unroute('**/v1/conversations');
    expectNoErrors(alice, bob, carol);
  });

  test('a conversation keeps the peer it was bound to when the list names another', async () => {
    const { page } = alice;
    // The list now says Alice's conversation with Bob is with Carol.
    await rewriteList(page, (items) => {
      const carolMember = conversationOf(items, carol.handle)!.members.find((member) => member.handle === carol.handle)!;
      const withBob = conversationOf(items, bob.handle)!;
      withBob.members = withBob.members.map((member) => (member.handle === bob.handle ? carolMember : member));
    });
    await reload(alice);
    await page.waitForTimeout(5_000);
    await expect(page.locator('.conv-item', { hasText: `@${bob.handle}` })).toHaveCount(1);
    await expect(page.locator('.conv-item', { hasText: `@${carol.handle}` })).toHaveCount(1);
    await openChatWith(alice, bob);
    await expect.poll(() => bubbleTexts(alice), { timeout: 15_000 }).toEqual(['bob says the code is 4471', 'thanks bob']);
    await expect(page.locator('.panel-msgs .group-meta', { hasText: `@${carol.handle}` })).toHaveCount(0);
    await expect(page.locator('.key-change-banner')).toHaveCount(0);

    // What Alice writes there still reaches Bob, and nothing reaches Carol.
    await send(alice, 'still for bob');
    await expect.poll(() => bubbleTexts(bob), { timeout: 15_000 }).toContain('still for bob');
    await page.waitForTimeout(2_000);
    expect(await bubbleTexts(carol)).not.toContain('still for bob');
    await page.unroute('**/v1/conversations');
    expectNoErrors(alice, bob, carol);
  });

  test('a conversation keeps showing its peer when the list renames our own entry in it', async () => {
    const { page } = alice;
    // The list now names Alice's own entry in her conversation with Bob as
    // Carol: Bob stays listed as himself.
    await rewriteList(page, (items) => {
      const withBob = conversationOf(items, bob.handle)!;
      for (const member of withBob.members) if (member.handle === alice.handle) member.handle = carol.handle;
    });
    await reload(alice);
    await page.waitForTimeout(5_000);
    expect((await page.locator('.conv-item .conv-name').allInnerTexts()).sort()).toEqual([`@${bob.handle}`, `@${carol.handle}`].sort());
    // Nor does a search for Carol find Bob's conversation.
    await page.fill('#search-input', carol.handle);
    await expect(page.locator('.conv-item .conv-name')).toHaveText([`@${carol.handle}`]);
    await page.fill('#search-input', '');

    await openChatWith(alice, bob);
    await expect.poll(() => bubbleTexts(alice), { timeout: 15_000 }).toContain('bob says the code is 4471');
    await expect(page.locator('#tab-strip .tab.active span').first()).toHaveText(`@${bob.handle}`);
    // Bob's messages are labelled with his handle, none with Carol's.
    const theirs = page.locator('.panel-msgs .msg-group.them .group-meta');
    await expect(theirs.first()).toBeVisible();
    for (const label of await theirs.allInnerTexts()) expect(label).toBe(`@${bob.handle}`);
    await expect(page.locator('.panel-msgs .group-meta', { hasText: `@${carol.handle}` })).toHaveCount(0);
    await expect(page.locator('.key-change-banner')).toHaveCount(0);
    await expect(page.locator('.account-conflict-banner')).toHaveCount(0);

    // Carol's own conversation is still hers alone.
    await openChatWith(alice, carol);
    await expect.poll(() => bubbleTexts(alice), { timeout: 15_000 }).toEqual(['hi from carol']);
    await page.unroute('**/v1/conversations');
    expectNoErrors(alice, bob, carol);
  });
});

test.describe('our own entry listed under a handle this device knows', () => {
  const id = stamp();
  let alice: Device;
  let bob: Device;
  let mallory: Device;
  let trudy: Device;

  test.beforeAll(async ({ browser }) => {
    await relay('/__test/reset');
    alice = await register(browser, `oalice${id}`);
    bob = await register(browser, `obob${id}`);
    mallory = await register(browser, `omal${id}`);
    trudy = await register(browser, `otru${id}`);
    await startChat(alice, bob);
    await send(bob, 'hi alice');
    await expect(rowOf(alice, 'hi alice')).toHaveCount(1, { timeout: 15_000 });
    await alice.page.locator('.panel-header .icon-btn', { hasText: '🛡' }).click();
    const dialog = alice.page.locator('#safety-dialog');
    await dialog.locator('button', { hasText: '확인됨으로 표시' }).click();
    await expect(dialog).toHaveCount(0);
  });

  test.afterAll(async () => {
    await closeAll(alice, bob, mallory, trudy);
  });

  async function startChatWithAlice(from: Device, text: string): Promise<void> {
    await from.page.click('#new-chat-btn');
    await from.page.fill('#new-peer-input', alice.handle);
    await from.page.click('#new-confirm');
    await expect(from.page.locator('.panel .panel-title .name')).toHaveText(`@${alice.handle}`);
    await send(from, text);
  }

  test("names a new conversation after its own peer, and holds it only when that peer is listed under the known handle", async () => {
    const { page } = alice;
    await expect(page.locator('.panel-header .verified-badge')).toBeVisible();
    // In every conversation with Mallory or Trudy the relay lists Alice's
    // own entry first, under Bob's handle. Mallory it lists as herself,
    // Trudy under Bob's handle too.
    await rewriteList(page, (items) => {
      for (const conv of items) {
        const handles = conv.members.map((member) => member.handle);
        const withTrudy = handles.includes(trudy.handle);
        if (!withTrudy && !handles.includes(mallory.handle)) continue;
        const own = conv.members.find((member) => member.handle === alice.handle)!;
        own.handle = bob.handle;
        if (withTrudy) for (const member of conv.members) if (member.handle === trudy.handle) member.handle = bob.handle;
        conv.members = [own, ...conv.members.filter((member) => member !== own)];
      }
    });

    // Mallory's conversation shows her own handle, and nothing stops it.
    await startChatWithAlice(mallory, 'bob here, new phone, send the code');
    const malloryRow = page.locator('.conv-item', { hasText: `@${mallory.handle}` });
    await expect(malloryRow).toHaveCount(1, { timeout: 15_000 });
    await expect(malloryRow).toContainText('bob here, new phone, send the code');
    await expect(page.locator('.conv-item', { hasText: `@${bob.handle}` })).toHaveCount(1);
    await malloryRow.click();
    await expect(page.locator('.panel .panel-title .name')).toHaveText(`@${mallory.handle}`);
    await expect(rowOf(alice, 'bob here, new phone, send the code')).toHaveCount(1, { timeout: 15_000 });
    await expect(page.locator('.panel-msgs .msg-group.them .group-meta')).toHaveText([`@${mallory.handle}`]);
    await expect(page.locator('#tab-strip .tab.active span').first()).toHaveText(`@${mallory.handle}`);
    await expect(page.locator('.account-conflict-banner')).toHaveCount(0);
    await expect(page.locator('.panel-header .verified-badge')).toBeHidden();
    // Nor does a search for Bob find it.
    await page.fill('#search-input', bob.handle);
    await expect(page.locator('.conv-item .conv-name')).toHaveText([`@${bob.handle}`]);
    await page.fill('#search-input', '');

    // Trudy's, listed under Bob's handle, is held.
    await startChatWithAlice(trudy, 'bob again, other phone');
    const rows = page.locator('.conv-item', { hasText: `@${bob.handle}` });
    await expect(rows).toHaveCount(2, { timeout: 15_000 });
    const held = rows.filter({ hasText: '⚠️ 같은 이름, 다른 계정' });
    await expect(held).toHaveCount(1);
    await held.click();
    await expect(page.locator('.account-conflict-banner')).toBeVisible();
    await expect(page.locator('.panel-input textarea')).toBeDisabled();
    await expect(page.locator('.panel-header .verified-badge')).toBeHidden();
    await expect(rowOf(alice, 'bob again, other phone')).toHaveCount(0);

    // A reload changes nothing.
    await reload(alice);
    await expect(page.locator('.conv-item', { hasText: `@${mallory.handle}` })).toHaveCount(1, { timeout: 15_000 });
    await expect(page.locator('.conv-item', { hasText: `@${bob.handle}` })).toHaveCount(2);
    await expect(page.locator('.conv-item', { hasText: '⚠️ 같은 이름, 다른 계정' })).toHaveCount(1);

    // The real Bob's conversation still shows him as verified.
    await page.locator('.conv-item', { hasText: 'hi alice' }).click();
    await expect(page.locator('.panel .panel-title .name')).toHaveText(`@${bob.handle}`);
    await expect(page.locator('.panel-header .verified-badge')).toBeVisible();
    await page.unroute('**/v1/conversations');
    expectNoErrors(alice, bob, mallory, trudy);
  });
});

test.describe('another account under a handle this device knows', () => {
  const id = stamp();
  let alice: Device;
  let bob: Device;
  let mallory: Device;

  test.beforeAll(async ({ browser }) => {
    await relay('/__test/reset');
    alice = await register(browser, `halice${id}`);
    bob = await register(browser, `hbob${id}`);
    mallory = await register(browser, `hmal${id}`);
    await startChat(alice, bob);
    await send(bob, 'hi alice');
    await expect(rowOf(alice, 'hi alice')).toHaveCount(1, { timeout: 15_000 });
    // Alice compares the safety number with Bob and marks it verified.
    await alice.page.locator('.panel-header .icon-btn', { hasText: '🛡' }).click();
    const dialog = alice.page.locator('#safety-dialog');
    await dialog.locator('button', { hasText: '확인됨으로 표시' }).click();
    await expect(dialog).toHaveCount(0);
  });

  test.afterAll(async () => {
    await closeAll(alice, bob, mallory);
  });

  test('is held until the user chooses to talk to it, and never looks verified', async () => {
    const { page } = alice;
    await expect(page.locator('.panel-header .verified-badge')).toBeVisible();
    await expect(page.locator('.panel-header .verified-badge')).toHaveText('✓ 확인됨');

    // The relay lists Mallory's new conversation with Alice under Bob's handle.
    await rewriteList(page, (items) => {
      for (const conv of items) {
        for (const member of conv.members) if (member.handle === mallory.handle) member.handle = bob.handle;
      }
    });
    await mallory.page.click('#new-chat-btn');
    await mallory.page.fill('#new-peer-input', alice.handle);
    await mallory.page.click('#new-confirm');
    await expect(mallory.page.locator('.panel .panel-title .name')).toHaveText(`@${alice.handle}`);
    await send(mallory, 'bob here, new phone, send the code');

    const rows = page.locator('.conv-item', { hasText: `@${bob.handle}` });
    await expect(rows).toHaveCount(2, { timeout: 15_000 });
    const lookalike = rows.filter({ hasText: '⚠️ 같은 이름, 다른 계정' });
    await expect(lookalike).toHaveCount(1);
    await lookalike.click();
    const banner = page.locator('.account-conflict-banner');
    await expect(banner).toBeVisible();
    await expect(banner.locator('.key-change-text')).toHaveText(
      `이 @${bob.handle} 은(는) 전에 대화한 @${bob.handle} 와(과) 다른 계정이에요. 그 사람인 척하는 누군가일 수 있어요: 이 계정과 대화하기로 하기 전까지 여기서는 아무것도 열거나 보내지 않아요.`,
    );
    await expect(page.locator('.panel-input textarea')).toBeDisabled();
    await expect(page.locator('.panel-header .verified-badge')).toBeHidden();
    await expect(rowOf(alice, 'bob here, new phone, send the code')).toHaveCount(0);
    await expect(page.locator('.panel-msgs .msg-row.them').last()).toContainText('🔒');

    // A reload changes nothing.
    await reload(alice);
    await page.locator('.conv-item', { hasText: '⚠️ 같은 이름, 다른 계정' }).click();
    await expect(page.locator('.account-conflict-banner')).toBeVisible();
    await expect(rowOf(alice, 'bob here, new phone, send the code')).toHaveCount(0);

    // Chosen as a different account after a confirmation, it is a first
    // contact like any other, still unverified.
    await page.locator('.account-conflict-banner button').click();
    await expect(page.locator('#confirm-title')).toHaveText(`다른 @${bob.handle} 계정과 대화할까요?`);
    await page.click('#confirm-ok');
    await expect(page.locator('.account-conflict-banner')).toHaveCount(0);
    await expect(rowOf(alice, 'bob here, new phone, send the code')).toHaveCount(1, { timeout: 15_000 });
    await expect(page.locator('.panel-input textarea')).toBeEnabled();
    await expect(page.locator('.panel-header .verified-badge')).toBeHidden();

    // The real Bob's conversation still shows him as verified.
    await page.locator('.conv-item', { hasText: 'hi alice' }).click();
    await expect(page.locator('.panel-header .verified-badge')).toBeVisible();
    expectNoErrors(alice, bob, mallory);
  });
});

test.describe('another account under a lookalike of a handle this device knows', () => {
  const id = stamp();
  let alice: Device;
  let bob: Device;
  let mallory: Device;

  test.beforeAll(async ({ browser }) => {
    await relay('/__test/reset');
    alice = await register(browser, `zalice${id}`);
    bob = await register(browser, `zbob${id}`);
    mallory = await register(browser, `zmal${id}`);
    await startChat(alice, bob);
    await send(bob, 'hi alice');
    await expect(rowOf(alice, 'hi alice')).toHaveCount(1, { timeout: 15_000 });
    await alice.page.locator('.panel-header .icon-btn', { hasText: '🛡' }).click();
    const dialog = alice.page.locator('#safety-dialog');
    await dialog.locator('button', { hasText: '확인됨으로 표시' }).click();
    await expect(dialog).toHaveCount(0);
  });

  test.afterAll(async () => {
    await closeAll(alice, bob, mallory);
  });

  test('is held, and shown for what it is, until the user chooses to talk to it', async () => {
    const { page } = alice;
    // The relay lists Mallory under Bob's handle with a zero-width space
    // after it: it renders as Bob's and equals no handle Alice knows.
    await rewriteList(page, (items) => {
      for (const conv of items) {
        for (const member of conv.members) if (member.handle === mallory.handle) member.handle = `${bob.handle}​`;
      }
    });
    await mallory.page.click('#new-chat-btn');
    await mallory.page.fill('#new-peer-input', alice.handle);
    await mallory.page.click('#new-confirm');
    await expect(mallory.page.locator('.panel .panel-title .name')).toHaveText(`@${alice.handle}`);
    await send(mallory, 'bob here, new phone, send the code');

    const shown = `@${bob.handle}[U+200B]`;
    const lookalike = page.locator('.conv-item', { hasText: '⚠️ VEIL이 발급하지 않는 이름' });
    await expect(lookalike).toHaveCount(1, { timeout: 15_000 });
    await expect(lookalike.locator('.conv-name')).toHaveText(shown);
    await lookalike.click();
    await expect(page.locator('.panel .panel-title .name')).toHaveText(shown);
    const banner = page.locator('.account-conflict-banner.unissued-handle');
    await expect(banner).toBeVisible();
    await expect(banner.locator('.key-change-text')).toContainText(`${shown} 은(는) VEIL이 발급하지 않는 이름이에요`);
    await expect(page.locator('.panel-input textarea')).toBeDisabled();
    await expect(page.locator('.panel-header .verified-badge')).toBeHidden();
    await expect(rowOf(alice, 'bob here, new phone, send the code')).toHaveCount(0);
    await expect(page.locator('.panel-msgs .msg-row.them').last()).toContainText('🔒');

    // A reload changes nothing.
    await reload(alice);
    await page.locator('.conv-item', { hasText: '⚠️ VEIL이 발급하지 않는 이름' }).click();
    await expect(page.locator('.account-conflict-banner.unissued-handle')).toBeVisible();
    await expect(rowOf(alice, 'bob here, new phone, send the code')).toHaveCount(0);

    // Chosen as a different account after a confirmation, it is a first
    // contact like any other, still unverified and still shown for what it is.
    await page.locator('.account-conflict-banner button').click();
    await expect(page.locator('#confirm-title')).toHaveText(`${shown} 와(과) 대화할까요?`);
    await page.click('#confirm-ok');
    await expect(page.locator('.account-conflict-banner')).toHaveCount(0);
    await expect(rowOf(alice, 'bob here, new phone, send the code')).toHaveCount(1, { timeout: 15_000 });
    await expect(page.locator('.panel-input textarea')).toBeEnabled();
    await expect(page.locator('.panel .panel-title .name')).toHaveText(shown);
    await expect(page.locator('.panel-header .verified-badge')).toBeHidden();
    // Its messages are named, and drawn, under the same shown form.
    await expect(page.locator('.panel-msgs .msg-group.them .group-meta').last()).toHaveText(shown);
    await expect(page.locator('.panel-msgs .msg-group.them > .avatar').last()).toHaveAttribute('title', shown.slice(1));

    // The real Bob's conversation still shows him as verified.
    await page.locator('.conv-item', { hasText: 'hi alice' }).click();
    await expect(page.locator('.panel .panel-title .name')).toHaveText(`@${bob.handle}`);
    await expect(page.locator('.panel-header .verified-badge')).toBeVisible();
    expectNoErrors(alice, bob, mallory);
  });
});

test.describe('another account under our own handle', () => {
  const id = stamp();
  let alice: Device;
  let mallory: Device;

  test.beforeAll(async ({ browser }) => {
    await relay('/__test/reset');
    alice = await register(browser, `walice${id}`);
    mallory = await register(browser, `wmal${id}`);
  });

  test.afterAll(async () => {
    await closeAll(alice, mallory);
  });

  test('is held until the user chooses to talk to it', async () => {
    const { page } = alice;
    // The relay lists Mallory's new conversation with Alice under Alice's
    // own handle: no other account can have it.
    await rewriteList(page, (items) => {
      for (const conv of items) {
        for (const member of conv.members) if (member.handle === mallory.handle) member.handle = alice.handle;
      }
    });
    await mallory.page.click('#new-chat-btn');
    await mallory.page.fill('#new-peer-input', alice.handle);
    await mallory.page.click('#new-confirm');
    await expect(mallory.page.locator('.panel .panel-title .name')).toHaveText(`@${alice.handle}`);
    await send(mallory, 'it is me, from my other phone');

    const held = page.locator('.conv-item', { hasText: '⚠️ 내 이름을 단 다른 계정' });
    await expect(held).toHaveCount(1, { timeout: 15_000 });
    await expect(held.locator('.conv-name')).toHaveText(`@${alice.handle}`);
    await held.click();
    const banner = page.locator('.account-conflict-banner.own-handle');
    await expect(banner).toBeVisible();
    await expect(banner.locator('.key-change-text')).toHaveText(
      `이 대화는 내 이름 @${alice.handle} (으)로 표시되지만 다른 계정이에요. 다른 사람은 내 이름을 가질 수 없어요: 이 기기가 받은 목록이 바뀐 것이고, 누군가를 나처럼 보이게 하려는 것일 수 있어요. 이 계정과 대화하기로 하기 전까지 여기서는 아무것도 열거나 보내지 않아요.`,
    );
    await expect(page.locator('.panel-input textarea')).toBeDisabled();
    await expect(page.locator('.panel-header .verified-badge')).toBeHidden();
    await expect(rowOf(alice, 'it is me, from my other phone')).toHaveCount(0);
    await expect(page.locator('.panel-msgs .msg-row.them').last()).toContainText('🔒');

    // A reload changes nothing.
    await reload(alice);
    await page.locator('.conv-item', { hasText: '⚠️ 내 이름을 단 다른 계정' }).click();
    await expect(page.locator('.account-conflict-banner.own-handle')).toBeVisible();
    await expect(rowOf(alice, 'it is me, from my other phone')).toHaveCount(0);

    // Chosen as a different account after a confirmation, it is a first
    // contact like any other, still unverified.
    await page.locator('.account-conflict-banner button').click();
    await expect(page.locator('#confirm-title')).toHaveText(`다른 @${alice.handle} 계정과 대화할까요?`);
    await page.click('#confirm-ok');
    await expect(page.locator('.account-conflict-banner')).toHaveCount(0);
    await expect(rowOf(alice, 'it is me, from my other phone')).toHaveCount(1, { timeout: 15_000 });
    await expect(page.locator('.panel-input textarea')).toBeEnabled();
    await expect(page.locator('.panel-header .verified-badge')).toBeHidden();
    await page.unroute('**/v1/conversations');
    expectNoErrors(alice, mallory);
  });
});
