import { expect, test, type Browser, type BrowserContext, type Page } from '@playwright/test';

// Protocol v2 in real Chrome against the in-memory relay (../mock-server.mjs):
// two browser contexts are two devices, each with its own IndexedDB. The
// relay has no realtime gateway, so both run in polling mode.

const RELAY = `http://127.0.0.1:${process.env.VEIL_MOCK_PORT ?? 4317}`;

interface Device {
  handle: string;
  context: BrowserContext;
  page: Page;
}

async function relay(path: string, body: unknown = {}): Promise<void> {
  const response = await fetch(RELAY + path, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
  expect(response.ok).toBe(true);
}

async function relayState<T>(path: string): Promise<T> {
  const response = await fetch(RELAY + path);
  expect(response.ok).toBe(true);
  return (await response.json()) as T;
}

// Records the page's ratchet work. Every session operation (decrypt
// included) holds a 'veil-crypto:<conversation>' Web Lock, and opening a
// protocol-v2 message runs HKDF (message keys) and often X25519 (DH steps);
// reading from the decrypt-once store does neither.
function recordCryptoWork(): void {
  const work = { derivations: [] as string[], sessionLocks: [] as string[] };
  Object.defineProperty(window, '__cryptoWork', { value: work });
  const deriveBits = SubtleCrypto.prototype.deriveBits;
  SubtleCrypto.prototype.deriveBits = function recordedDeriveBits(algorithm, key, length) {
    work.derivations.push(typeof algorithm === 'string' ? algorithm : algorithm.name);
    return deriveBits.call(this, algorithm, key, length);
  };
  const request = LockManager.prototype.request as (...args: unknown[]) => Promise<unknown>;
  LockManager.prototype.request = function recordedRequest(name: string, ...rest: unknown[]) {
    if (name.startsWith('veil-crypto:')) work.sessionLocks.push(name);
    return request.call(this, name, ...rest);
  } as typeof LockManager.prototype.request;
}

const cryptoWork = (page: Page) =>
  page.evaluate(() => {
    const { derivations, sessionLocks } = (window as unknown as {
      __cryptoWork: { derivations: string[]; sessionLocks: string[] };
    }).__cryptoWork;
    return { derivations: derivations.slice(), sessionLocks: sessionLocks.slice() };
  });

async function register(browser: Browser, handle: string): Promise<Device> {
  const context = await browser.newContext();
  await context.addInitScript(recordCryptoWork);
  const page = await context.newPage();
  await page.goto('./');
  await page.fill('#reg-handle', handle);
  await page.click('#reg-btn');
  await expect(page.locator('#app')).toBeVisible();
  return { handle, context, page };
}

async function openChatWith(device: Device, peer: Device): Promise<void> {
  const row = device.page.locator('.conv-item', { hasText: `@${peer.handle}` });
  await expect(row).toBeVisible({ timeout: 15_000 });
  await row.click();
  await expect(device.page.locator('.panel .panel-title .name')).toHaveText(`@${peer.handle}`);
}

async function send(device: Device, text: string): Promise<void> {
  const textarea = device.page.locator('.panel-input textarea').first();
  await textarea.fill(text);
  await textarea.press('Enter');
  // Sent, not just pending: the relay has stored it.
  await expect(device.page.locator('.msg-row.me:not(:has(.msg.pending))', { hasText: text })).toHaveCount(1);
}

const bubbleTexts = (device: Device) => device.page.locator('.panel-msgs .msg-row .msg-text').allInnerTexts();

async function startChat(from: Device, to: Device): Promise<void> {
  await from.page.click('#new-chat-btn');
  await from.page.fill('#new-peer-input', to.handle);
  await from.page.click('#new-confirm');
  await expect(from.page.locator('.panel .panel-title .name')).toHaveText(`@${to.handle}`);
  await openChatWith(to, from);
}

// Each text goes through the composer in one synchronous step, and the next
// only once its bubble shows: the panel is rebuilt on every poll and send,
// and a keypress that lands while it is drops, so a fill-then-press per
// message would lose one now and then in a long run.
async function sendAll(device: Device, texts: string[]): Promise<void> {
  await device.page.evaluate(async (all) => {
    const own = () => document.querySelectorAll('.panel-msgs .msg-row.me').length;
    for (const text of all) {
      const before = own();
      const textarea = document.querySelector('.panel-input textarea') as HTMLTextAreaElement;
      textarea.value = text;
      textarea.dispatchEvent(new Event('input', { bubbles: true }));
      textarea.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true }));
      while (own() === before) await new Promise((resolve) => setTimeout(resolve, 5));
    }
  }, texts);
}

// Opens a message's action menu and clicks one of its items; a rebuilt
// panel closes the menu, so it is opened again until the click lands.
async function chooseAction(device: Device, text: string, item: string): Promise<void> {
  const row = device.page.locator('.panel-msgs .msg-row', { hasText: text });
  await expect(async () => {
    await row.click({ button: 'right' });
    await device.page.locator('.msg-action-menu .msg-action-item', { hasText: item }).click({ timeout: 2_000 });
  }).toPass({ timeout: 30_000 });
}

interface StoredContent {
  retired: boolean;
  sealed: boolean;
}

// What the page's decrypt-once store holds per message id, read through the
// app's own IndexedDB module.
const storedContents = (page: Page) =>
  page.evaluate(async () => {
    const { createIdb } = await import('./src/platform/idb.js');
    const idb = createIdb(indexedDB);
    const rows = (await idb.all('message-contents')) as Array<Record<string, unknown>>;
    await idb.close();
    return Object.fromEntries(rows.map((row) => [row.id as string, { retired: row.retired === true, sealed: 'sealed' in row }]));
  }) as Promise<Record<string, StoredContent>>;

test.describe.configure({ mode: 'serial' });

test.describe('protocol v2 in the browser', () => {
  const stamp = Date.now().toString(36).slice(-6);
  const script: Array<['alice' | 'bob', string]> = [
    ['alice', 'a1 hello bob'],
    ['alice', 'a2 still me'],
    ['bob', 'b1 hi alice'],
    ['alice', 'a3 crossing'],
    ['bob', 'b2 crossing too'],
    ['bob', 'b3 and again'],
    ['alice', 'a4 one more'],
    ['bob', 'b4 nearly done'],
    ['alice', 'a5 last from alice'],
    ['bob', 'b5 last from bob'],
  ];
  const texts = script.map(([, text]) => text);
  let alice: Device;
  let bob: Device;

  test.beforeAll(async ({ browser }) => {
    await relay('/__test/reset');
    alice = await register(browser, `alice${stamp}`);
    bob = await register(browser, `bob${stamp}`);
  });

  test.afterAll(async () => {
    await alice?.context.close();
    await bob?.context.close();
  });

  test('Alice and Bob exchange 10 messages with shuffled delivery', async () => {
    await relay('/__test/delivery', { shuffle: true });
    await startChat(alice, bob);

    // Neither side waits for the other, so frames cross and arrive out of
    // order: Bob may even start a session of his own before Alice's lands.
    for (const [sender, text] of script) await send(sender === 'alice' ? alice : bob, text);

    for (const device of [alice, bob]) {
      await expect.poll(() => bubbleTexts(device), { timeout: 60_000 }).toEqual(texts);
      await expect(device.page.locator('.panel-msgs')).not.toContainText('🔒');
      // The counter the next test relies on does see ratchet work.
      const work = await cryptoWork(device.page);
      expect(work.derivations).toEqual(expect.arrayContaining(['HKDF', 'X25519']));
      expect(work.sessionLocks.length).toBeGreaterThan(0);
    }
  });

  test('reload restores history with zero decrypt calls', async () => {
    await relay('/__test/delivery', { shuffle: false });
    // From now on the relay serves every ciphertext corrupted: whatever the
    // pages show after the reload can only come from their own stores.
    await relay('/__test/tamper', { enabled: true });
    for (const [device, peer] of [[alice, bob], [bob, alice]] as const) {
      await device.page.reload();
      await expect(device.page.locator('#app')).toBeVisible();
      await openChatWith(device, peer);
      await expect.poll(() => bubbleTexts(device), { timeout: 15_000 }).toEqual(texts);
      // Let a polling round re-fetch the (corrupted) history as well.
      await device.page.waitForTimeout(5_000);
      expect(await bubbleTexts(device)).toEqual(texts);
      await expect(device.page.locator('.panel-msgs')).not.toContainText('🔒');
      expect(await cryptoWork(device.page)).toEqual({ derivations: [], sessionLocks: [] });
    }
  });

  // Each side's dialog is computed from the identity its session runs on;
  // with nobody in the middle the two numbers are the same.
  test('both devices show the same safety number', async () => {
    const numbers: string[] = [];
    for (const device of [alice, bob]) {
      await device.page.locator('.panel .icon-btn', { hasText: '🛡' }).click();
      const shown = device.page.locator('#safety-dialog #safety-number');
      await expect(shown).toBeVisible();
      numbers.push((await shown.innerText()).trim());
      await device.page.keyboard.press('Escape');
      await expect(device.page.locator('#safety-dialog')).toHaveCount(0);
    }
    expect(numbers[0].replace(/\s/g, '')).toMatch(/^\d{60}$/);
    expect(numbers[0]).toBe(numbers[1]);
  });

  // The banner stops nothing: Alice keeps writing to the key she has, and
  // the relay's key reads none of it.
  test('relay identity swap shows banner and keeps sending to the pinned key', async () => {
    await relay('/__test/tamper', { enabled: false });
    // The relay takes over Bob's directory entry with an identity it holds
    // and opens a session to Alice as Bob's device.
    await relay('/__test/impersonate', { victim: bob.handle, target: alice.handle, text: 'relay pretending to be bob' });

    const page = alice.page;
    await expect(page.locator('.key-change-banner')).toBeVisible({ timeout: 15_000 });
    await expect(page.locator('.key-change-banner')).toContainText(`@${bob.handle}`);
    await expect(page.locator('.panel-input textarea')).toBeEnabled();
    await expect(page.locator('.panel-msgs')).not.toContainText('relay pretending to be bob');
    // The relay's message is refused, not shown.
    await expect(page.locator('.panel-msgs .msg-row.them').last()).toContainText('🔒');
    await expect(page.locator('.conv-item', { hasText: `@${bob.handle}` })).toContainText('⚠️');
    // The history from before the swap is untouched.
    expect((await bubbleTexts(alice)).slice(0, texts.length)).toEqual(texts);
    await send(alice, 'while the banner shows');
    await expect.poll(() => bubbleTexts(bob), { timeout: 30_000 }).toContain('while the banner shows');
    await expect(page.locator('.key-change-banner')).toBeVisible();
  });

  // The refused frame stays on the relay, and every history refresh and
  // reload opens it again: once declined, it raises nothing.
  test('declining the relay key resumes the conversation, across a reload', async () => {
    const page = alice.page;
    await page.locator('.key-change-banner .key-change-decline').click();
    await page.locator('#confirm-ok').click();
    await expect(page.locator('.key-change-banner')).toHaveCount(0);
    await send(alice, 'after declining');
    await expect.poll(() => bubbleTexts(bob), { timeout: 30_000 }).toContain('after declining');

    await page.reload();
    await expect(page.locator('#app')).toBeVisible();
    await openChatWith(alice, bob);
    await expect.poll(() => bubbleTexts(alice), { timeout: 15_000 }).toContain('after declining');
    // Let a polling round fetch the refused frame from the relay as well.
    await page.waitForTimeout(5_000);
    await expect(page.locator('.key-change-banner')).toHaveCount(0);
    await expect(page.locator('.panel-msgs .msg-row.them').last()).toContainText('🔒');
    await send(alice, 'after reloading');
    await expect.poll(() => bubbleTexts(bob), { timeout: 30_000 }).toContain('after reloading');
  });

  // The relay checks the body as the API's FileAbuseReportDto does, and
  // keeps what it was sent.
  test('a report sends the reason and the ids of the message, and no text', async () => {
    await chooseAction(alice, 'b1 hi alice', '🚨');
    await alice.page.locator('#report-dialog input[value="spam"]').check();
    await alice.page.locator('#report-submit').click();
    await expect(alice.page.locator('#report-dialog')).toHaveCount(0);

    type Report = { reporterHandle: string; reportedHandle: string; body: Record<string, string> };
    await expect.poll(async () => (await relayState<Report[]>('/__test/reports')).length, { timeout: 10_000 }).toBe(1);
    const [report] = await relayState<Report[]>('/__test/reports');
    const messageId = await alice.page.locator('.panel-msgs .msg-row', { hasText: 'b1 hi alice' }).getAttribute('data-msg-id');
    expect(report).toMatchObject({ reporterHandle: alice.handle, reportedHandle: bob.handle });
    expect(Object.keys(report.body).sort()).toEqual(['conversationId', 'messageId', 'reason', 'reportedUserId']);
    expect(report.body).toMatchObject({ messageId, reason: 'spam' });
  });
});

// History is fetched a page at a time, newest first. A device that was away
// while more than a page arrived gets all of it, and opens its ratchet
// chain in order: a frame at the top of a long backlog, opened first, would
// need more skipped keys than one frame may stash. Reactions are messages
// too, so they fill pages without being bubbles.
test.describe('a backlog longer than a page', () => {
  const stamp = Date.now().toString(36).slice(-6);
  const BACKLOG = 260;
  const label = (n: number) => `m${String(n).padStart(3, '0')} backlog`;
  const backlog = Array.from({ length: BACKLOG }, (_, i) => label(i + 1));
  // Erin reacts to these of her messages while Frank is away.
  const reacted = [label(50), label(150), label(250)];
  let erin: Device;
  let frank: Device;

  test.beforeAll(async ({ browser }) => {
    await relay('/__test/reset');
    erin = await register(browser, `erin${stamp}`);
    frank = await register(browser, `frank${stamp}`);
  });

  test.afterAll(async () => {
    await erin?.context.close();
    await frank?.context.close();
  });

  async function react(device: Device, text: string): Promise<void> {
    const row = device.page.locator('.panel-msgs .msg-row', { hasText: text });
    await expect(row.locator('.msg:not(.pending)')).toHaveCount(1);
    // A rebuilt panel closes the menu; open it again until the click lands.
    await expect(async () => {
      await row.click({ button: 'right' });
      await device.page.locator('.msg-action-menu .msg-action-row button').first().click({ timeout: 2_000 });
    }).toPass({ timeout: 30_000 });
    await expect(row.locator('.msg-reaction-chip')).toHaveCount(1);
  }

  test('is fetched whole and opened in order, and stays after a refresh', async () => {
    test.setTimeout(300_000);
    await startChat(erin, frank);
    await send(erin, label(0));
    await expect.poll(() => bubbleTexts(frank), { timeout: 20_000 }).toEqual([label(0)]);
    // Frank goes away; his keys and history stay in his browser profile.
    await frank.page.close();

    let sent = 0;
    for (const target of reacted) {
      const through = backlog.indexOf(target) + 1;
      await sendAll(erin, backlog.slice(sent, through));
      sent = through;
      await react(erin, target);
    }
    await sendAll(erin, backlog.slice(sent));
    await expect(erin.page.locator('.msg-row.me:not(:has(.msg.pending))')).toHaveCount(BACKLOG + 1, { timeout: 60_000 });

    frank.page = await frank.context.newPage();
    await frank.page.goto('./');
    await expect(frank.page.locator('#app')).toBeVisible();
    await openChatWith(frank, erin);
    const everything = [label(0), ...backlog];
    await expect.poll(() => bubbleTexts(frank), { timeout: 120_000 }).toEqual(everything);
    await expect(frank.page.locator('.panel-msgs')).not.toContainText('🔒');
    for (const text of reacted) {
      await expect(frank.page.locator('.panel-msgs .msg-row', { hasText: text }).locator('.msg-reaction-chip')).toHaveCount(1);
    }

    // Later refreshes fetch only the newest page; nothing drops out.
    await frank.page.waitForTimeout(5_000);
    expect(await bubbleTexts(frank)).toEqual(everything);
    await frank.page.reload();
    await expect(frank.page.locator('#app')).toBeVisible();
    await openChatWith(frank, erin);
    await expect.poll(() => bubbleTexts(frank), { timeout: 30_000 }).toEqual(everything);
    await frank.page.waitForTimeout(5_000);
    expect(await bubbleTexts(frank)).toEqual(everything);
    await expect(frank.page.locator('.panel-msgs')).not.toContainText('🔒');
  });
});

// Our own send is cached the moment the relay acknowledges it, above a
// backlog no refresh has fetched yet. After a reload the backlog is still
// paged back through: how far history was fetched is kept apart from what
// the cache holds (src/domain/history.js createHistoryMarks).
test.describe('a backlog under our own send', () => {
  const stamp = Date.now().toString(36).slice(-6);
  const BACKLOG = 260;
  const label = (n: number) => `g${String(n).padStart(3, '0')} gap`;
  const backlog = Array.from({ length: BACKLOG }, (_, i) => label(i + 1));
  const HISTORY = '**/v1/conversations/*/messages*';
  let erin: Device;
  let frank: Device;

  test.beforeAll(async ({ browser }) => {
    await relay('/__test/reset');
    erin = await register(browser, `gerin${stamp}`);
    frank = await register(browser, `gfrank${stamp}`);
  });

  test.afterAll(async () => {
    await erin?.context.close();
    await frank?.context.close();
  });

  test('is fetched after a reload, in order, with nothing locked', async () => {
    test.setTimeout(300_000);
    await startChat(erin, frank);
    await send(erin, label(0));
    await expect.poll(() => bubbleTexts(frank), { timeout: 20_000 }).toEqual([label(0)]);
    await frank.page.close();
    await sendAll(erin, backlog);
    await expect(erin.page.locator('.msg-row.me:not(:has(.msg.pending))')).toHaveCount(BACKLOG + 1, { timeout: 60_000 });

    // Frank comes back while every history fetch fails; his own send goes
    // through and is cached at the top of the conversation.
    frank.page = await frank.context.newPage();
    await frank.page.route(HISTORY, (route) => route.abort());
    await frank.page.goto('./');
    await expect(frank.page.locator('#app')).toBeVisible();
    await openChatWith(frank, erin);
    await send(frank, 'frank on top');
    await frank.page.unroute(HISTORY);

    await frank.page.reload();
    await expect(frank.page.locator('#app')).toBeVisible();
    await openChatWith(frank, erin);
    const everything = [label(0), ...backlog, 'frank on top'];
    await expect.poll(() => bubbleTexts(frank), { timeout: 120_000 }).toEqual(everything);
    await expect(frank.page.locator('.panel-msgs')).not.toContainText('🔒');
  });
});

// Contract C4 and deletion on the device: once a message is deleted or its
// expiry passes, it leaves the panel and the sidebar, and its row in the
// decrypt-once store is retired, on the sender's device and the
// recipient's alike, with history polling as the only channel.
test.describe('deleted and expired messages in the browser', () => {
  const stamp = Date.now().toString(36).slice(-6);
  const DELETED = '🚫 삭제된 메시지';
  let carol: Device;
  let dave: Device;

  test.beforeAll(async ({ browser }) => {
    await relay('/__test/reset');
    carol = await register(browser, `carol${stamp}`);
    dave = await register(browser, `dave${stamp}`);
  });

  test.afterAll(async () => {
    await relay('/__test/timer', { seconds: null });
    await carol?.context.close();
    await dave?.context.close();
  });

  test('leave the page and the decrypt-once store', async () => {
    const sweepFailures: string[] = [];
    for (const device of [carol, dave]) {
      device.page.on('console', (message) => {
        if (message.text().includes('expiry sweep failed')) sweepFailures.push(message.text());
      });
    }
    await startChat(carol, dave);
    await send(carol, 'lasting note');
    await send(carol, 'regretted note');
    // The relay's conversation timer: only the last message expires.
    await relay('/__test/timer', { seconds: 30 });
    await send(carol, 'vanishing note');
    await relay('/__test/timer', { seconds: null });

    const sent = ['lasting note', 'regretted note', 'vanishing note'];
    for (const device of [carol, dave]) await expect.poll(() => bubbleTexts(device), { timeout: 20_000 }).toEqual(sent);
    const idOf = async (text: string) =>
      (await dave.page.locator('.panel-msgs .msg-row', { hasText: text }).getAttribute('data-msg-id')) as string;
    const [lasting, regretted, vanishing] = await Promise.all(sent.map(idOf));
    for (const device of [carol, dave]) {
      const stored = await storedContents(device.page);
      for (const id of [lasting, regretted, vanishing]) expect(stored[id]).toEqual({ retired: false, sealed: true });
    }

    await carol.page.locator('.panel-msgs .msg-row.me', { hasText: 'regretted note' }).click({ button: 'right' });
    await carol.page.locator('.msg-action-item.danger').click();
    await carol.page.locator('#confirm-ok').click();
    for (const device of [carol, dave]) {
      await expect.poll(() => bubbleTexts(device), { timeout: 20_000 }).toContain(DELETED);
      expect(await bubbleTexts(device)).not.toContain('regretted note');
    }

    for (const device of [carol, dave]) {
      await expect.poll(() => bubbleTexts(device), { timeout: 45_000 }).toEqual(['lasting note', DELETED]);
      await expect(device.page.locator('.conv-list')).not.toContainText('vanishing note');
      const stored = await storedContents(device.page);
      expect(stored[lasting]).toEqual({ retired: false, sealed: true });
      for (const id of [regretted, vanishing]) expect(stored[id]).toEqual({ retired: true, sealed: false });
    }

    // A reload, with the relay still serving the expired message, brings
    // nothing back.
    await dave.page.reload();
    await expect(dave.page.locator('#app')).toBeVisible();
    await openChatWith(dave, carol);
    await expect.poll(() => bubbleTexts(dave), { timeout: 15_000 }).toEqual(['lasting note', DELETED]);
    expect(sweepFailures).toEqual([]);
  });

  // The relay stores the message with no outer expiresAt, though the
  // conversation has a timer: the expiry sealed inside it is what removes it.
  test('a relay that drops the outer expiry cannot keep a disappearing message', async () => {
    await relay('/__test/timer', { seconds: 20, relayExpiry: false });
    // The sender learns the timer from the conversation list it polls.
    await carol.page.waitForTimeout(6_000);
    await send(carol, 'sealed timer note');
    await relay('/__test/timer', { seconds: null });
    for (const device of [carol, dave]) await expect.poll(() => bubbleTexts(device), { timeout: 20_000 }).toContain('sealed timer note');
    const id = await dave.page.locator('.panel-msgs .msg-row', { hasText: 'sealed timer note' }).getAttribute('data-msg-id') as string;
    for (const device of [carol, dave]) {
      await expect.poll(() => bubbleTexts(device), { timeout: 45_000 }).not.toContain('sealed timer note');
      expect((await storedContents(device.page))[id]).toEqual({ retired: true, sealed: false });
    }
  });

  test('the store retires expired records it is not showing', async ({ browser }) => {
    const context = await browser.newContext();
    const page = await context.newPage();
    await page.goto('./s.html');
    const rows = await page.evaluate(async () => {
      const { createIdb } = await import('./src/platform/idb.js');
      const { createIdbKv } = await import('./src/platform/kv.js');
      const { createContentStore } = await import('./src/platform/content-store.js');
      const { createLocks } = await import('./src/crypto/locks.js');
      const idb = createIdb(indexedDB);
      const store = createContentStore({
        subtle: crypto.subtle,
        random: (length: number) => crypto.getRandomValues(new Uint8Array(length)),
        records: createIdbKv(idb, 'message-contents', { index: 'byConversation', expiryIndex: 'byExpiry' }),
        keys: createIdbKv(idb, 'content-keys'),
        locks: createLocks(navigator.locks),
      });
      const value = (text: string) => ({ content: { kind: 'text', text }, nonce: 'n' });
      await store.put('c-1', 'm-past', value('expired'), { expiresAt: 1_000 });
      await store.put('c-1', 'm-future', value('later'), { expiresAt: 3_000 });
      await store.put('c-1', 'm-forever', value('kept'));
      await store.retireExpired(2_000);
      const stored = (await idb.all('message-contents')) as Array<Record<string, unknown>>;
      const shown = await Promise.all(['m-past', 'm-future', 'm-forever'].map((id) => store.get('c-1', id)));
      await idb.close();
      return {
        rows: Object.fromEntries(stored.map((row) => [row.id as string, { retired: row.retired === true, sealed: 'sealed' in row }])),
        shown: shown.map((entry) => (entry as { retired?: boolean; content?: { text: string } }).retired ?? entry.content?.text),
      };
    });
    expect(rows).toEqual({
      rows: {
        'm-past': { retired: true, sealed: false },
        'm-future': { retired: false, sealed: true },
        'm-forever': { retired: false, sealed: true },
      },
      shown: [true, 'later', 'kept'],
    });
    await context.close();
  });
});

// A disappearing message's expiry is an absolute time, stamped by the sender
// and judged by the recipient, each on its clock corrected toward the
// relay's (src/core/expiry.js). Here the sender's clock runs 40 s slow and
// the recipient's 40 s fast, and the relay sets no outer expiry: on the raw
// clocks the 20 s message would be past on arrival and never shown.
test.describe('disappearing messages between clocks that disagree', () => {
  const stamp = Date.now().toString(36).slice(-6);
  let slow: Device;
  let fast: Device;

  async function registerSkewed(browser: Browser, handle: string, skewMs: number): Promise<Device> {
    const context = await browser.newContext();
    await context.clock.install({ time: Date.now() + skewMs });
    const page = await context.newPage();
    await page.goto('./');
    await page.fill('#reg-handle', handle);
    await page.click('#reg-btn');
    await expect(page.locator('#app')).toBeVisible();
    return { handle, context, page };
  }

  test.beforeAll(async ({ browser }) => {
    await relay('/__test/reset');
    slow = await registerSkewed(browser, `slow${stamp}`, -40_000);
    fast = await registerSkewed(browser, `fast${stamp}`, 40_000);
  });

  test.afterAll(async () => {
    await relay('/__test/timer', { seconds: null });
    await slow?.context.close();
    await fast?.context.close();
  });

  test('shows the message for its timer, then removes it', async () => {
    await startChat(slow, fast);
    expect(await slow.page.evaluate(() => Date.now())).toBeLessThan(Date.now() - 30_000);
    expect(await fast.page.evaluate(() => Date.now())).toBeGreaterThan(Date.now() + 30_000);
    await relay('/__test/timer', { seconds: 20, relayExpiry: false });
    // The sender learns the timer from the conversation list it polls.
    await slow.page.waitForTimeout(6_000);
    await send(slow, 'skewed timer note');
    await relay('/__test/timer', { seconds: null });

    await expect.poll(() => bubbleTexts(fast), { timeout: 15_000 }).toContain('skewed timer note');
    for (const device of [slow, fast]) {
      await expect.poll(() => bubbleTexts(device), { timeout: 45_000 }).not.toContain('skewed timer note');
    }
  });
});

// Two tabs of one browser profile share the session record in IndexedDB,
// each with its own copy in memory: prekey maintenance in one and token
// renewals in the other must not revert each other's fields. Each tab runs
// the app's own session store and IndexedDB repo, published on window.
interface SharedRecord {
  nextOneTimePrekeyId: number;
  signedPrekeys: Array<{ id: number }>;
  accessToken: string | null;
}
interface TabSession {
  repo: { put(record: unknown): Promise<void> };
  store: {
    load(): Promise<unknown>;
    reload(): Promise<SharedRecord>;
    update(fields: Partial<SharedRecord>): Promise<void>;
    saveTokens(tokens: { accessToken: string; refreshToken: string }): Promise<void>;
    clearTokens(): Promise<void>;
  };
}

async function openTab(context: BrowserContext): Promise<Page> {
  const tab = await context.newPage();
  // Any page of the origin will do; the secret-link page leaves the
  // database alone.
  await tab.goto('./s.html');
  await tab.evaluate(async () => {
    const { createIdb } = await import('./src/platform/idb.js');
    const { createIdbSessionRepo, createSessionStore } = await import('./src/platform/session-store.js');
    const repo = createIdbSessionRepo(createIdb(indexedDB));
    const store = createSessionStore({ repo, subtle: crypto.subtle });
    Object.defineProperty(window, '__session', { value: { repo, store } });
  });
  return tab;
}

test.describe('session record shared by two tabs', () => {
  test('a token save in one tab keeps the prekey state another tab saved', async ({ browser }) => {
    const context = await browser.newContext();
    const [maintainer, renewer] = [await openTab(context), await openTab(context)];

    await maintainer.evaluate(async () => {
      const { repo } = (window as unknown as { __session: TabSession }).__session;
      await repo.put({
        handle: 'alice',
        edPubB64u: 'alice-auth-key',
        signedPrekeys: [{ id: 1 }],
        nextOneTimePrekeyId: 1,
        accessToken: 'access-0',
        refreshToken: 'refresh-0',
      });
    });
    for (const tab of [maintainer, renewer]) {
      await tab.evaluate(async () => {
        await (window as unknown as { __session: TabSession }).__session.store.load();
      });
    }

    // Both tabs write at once, each from the copy it loaded.
    await Promise.all([
      maintainer.evaluate(async () => {
        const { store } = (window as unknown as { __session: TabSession }).__session;
        for (let round = 1; round <= 20; round += 1) {
          await store.update({
            nextOneTimePrekeyId: 1 + round * 100,
            signedPrekeys: Array.from({ length: round + 1 }, (_, i) => ({ id: round + 1 - i })),
          });
        }
      }),
      renewer.evaluate(async () => {
        const { store } = (window as unknown as { __session: TabSession }).__session;
        for (let round = 1; round <= 20; round += 1) {
          await store.saveTokens({ accessToken: `access-${round}`, refreshToken: `refresh-${round}` });
        }
      }),
    ]);
    // And once more after all of the maintainer's writes have landed.
    await renewer.evaluate(async () => {
      await (window as unknown as { __session: TabSession }).__session.store.clearTokens();
    });

    for (const tab of [maintainer, renewer]) {
      const stored = await tab.evaluate(async () => {
        const record = await (window as unknown as { __session: TabSession }).__session.store.reload();
        return { next: record.nextOneTimePrekeyId, spks: record.signedPrekeys.length, token: record.accessToken };
      });
      expect(stored).toEqual({ next: 2001, spks: 21, token: null });
    }
    await context.close();
  });
});
