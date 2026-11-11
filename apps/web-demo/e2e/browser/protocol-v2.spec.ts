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
    await alice.page.click('#new-chat-btn');
    await alice.page.fill('#new-peer-input', bob.handle);
    await alice.page.click('#new-confirm');
    await expect(alice.page.locator('.panel .panel-title .name')).toHaveText(`@${bob.handle}`);
    await openChatWith(bob, alice);

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

  test('relay identity swap shows banner and disables send', async () => {
    await relay('/__test/tamper', { enabled: false });
    // The relay takes over Bob's directory entry with an identity it holds
    // and opens a session to Alice as Bob's device.
    await relay('/__test/impersonate', { victim: bob.handle, target: alice.handle, text: 'relay pretending to be bob' });

    const page = alice.page;
    await expect(page.locator('.key-change-banner')).toBeVisible({ timeout: 15_000 });
    await expect(page.locator('.key-change-banner')).toContainText(`@${bob.handle}`);
    await expect(page.locator('.panel-input textarea')).toBeDisabled();
    await expect(page.locator('.send-btn')).toBeDisabled();
    await expect(page.locator('.panel-msgs')).not.toContainText('relay pretending to be bob');
    // The relay's message is refused, not shown.
    await expect(page.locator('.panel-msgs .msg-row.them').last()).toContainText('🔒');
    await expect(page.locator('.conv-item', { hasText: `@${bob.handle}` })).toContainText('⚠️');
    // The history from before the swap is untouched.
    expect((await bubbleTexts(alice)).slice(0, texts.length)).toEqual(texts);
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
