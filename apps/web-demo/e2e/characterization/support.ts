import { expect, type Browser, type BrowserContext, type Page } from '@playwright/test';

// Shared steps for the characterization tests: each drives the real app
// (index.html + app.js) through its UI in its own browser context, one per
// device, against the in-memory relay (../mock-server.mjs).

const RELAY = `http://127.0.0.1:${process.env.VEIL_MOCK_PORT ?? 4317}`;

export interface Device {
  handle: string;
  context: BrowserContext;
  page: Page;
  // Uncaught exceptions and error-level console output of every page this
  // device opened.
  errors: string[];
}

export const stamp = () => Date.now().toString(36).slice(-6);

export async function relay(path: string, body: unknown = {}): Promise<void> {
  const response = await fetch(RELAY + path, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
  expect(response.ok).toBe(true);
}

// Chrome itself logs a refused request, the realtime upgrade a relay
// without a gateway turns down, and that index.html's meta CSP cannot carry
// frame-ancestors (the serving layer's header does); none is the app's error.
const BROWSER_LOG = /^(Failed to load resource|WebSocket connection to|The Content Security Policy directive 'frame-ancestors')/;

export function watchErrors(page: Page, errors: string[]): void {
  page.on('console', (message) => {
    if (message.type() === 'error' && !BROWSER_LOG.test(message.text())) errors.push(message.text());
  });
  page.on('pageerror', (error) => errors.push(error.message));
}

// A browser profile with the app open on its auth screen, in Korean, the
// language most of the app's strings are written in.
export async function openDevice(browser: Browser, handle: string): Promise<Device> {
  const context = await browser.newContext({ acceptDownloads: true, locale: 'ko-KR' });
  const page = await context.newPage();
  const device = { handle, context, page, errors: [] as string[] };
  watchErrors(page, device.errors);
  // The auth screen is in the HTML before any script runs; once the network
  // is idle the modules have loaded and their listeners are attached, so a
  // click cannot submit the form natively.
  await page.goto('./', { waitUntil: 'networkidle' });
  await expect(page.locator('#auth-screen')).toBeVisible();
  return device;
}

export async function register(browser: Browser, handle: string): Promise<Device> {
  const device = await openDevice(browser, handle);
  await device.page.fill('#reg-handle', handle);
  await device.page.click('#reg-btn');
  await expect(device.page.locator('#app')).toBeVisible();
  return device;
}

// Opens the app again in a new page of the device's profile.
export async function reopen(device: Device): Promise<void> {
  device.page = await device.context.newPage();
  watchErrors(device.page, device.errors);
  await device.page.goto('./');
}

export async function reload(device: Device): Promise<void> {
  await device.page.reload();
  await expect(device.page.locator('#app')).toBeVisible();
}

export async function openChatWith(device: Device, peer: Device): Promise<void> {
  const row = device.page.locator('.conv-item', { hasText: `@${peer.handle}` });
  await expect(row).toBeVisible({ timeout: 15_000 });
  await row.click();
  await expect(device.page.locator('.panel .panel-title .name').first()).toHaveText(`@${peer.handle}`);
}

export async function startChat(from: Device, to: Device): Promise<void> {
  await from.page.click('#new-chat-btn');
  await from.page.fill('#new-peer-input', to.handle);
  await from.page.click('#new-confirm');
  await expect(from.page.locator('.panel .panel-title .name')).toHaveText(`@${to.handle}`);
  await openChatWith(to, from);
}

// The panel is rebuilt on every poll and send, and a keypress that lands
// while it is drops, so the text goes in and is sent in one step. `shown` is
// the bubble's text once rendered (markdown takes its markers out).
export async function send(device: Device, text: string, shown = text): Promise<void> {
  await device.page.evaluate((body) => {
    const textarea = document.querySelector('.panel-input textarea') as HTMLTextAreaElement;
    textarea.value = body;
    textarea.dispatchEvent(new Event('input', { bubbles: true }));
    textarea.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true }));
  }, text);
  await expect(rowOf(device, shown, '.me:not(:has(.msg.pending))')).toHaveCount(1);
}

// Sends each text once the bubble of the one before shows.
export async function sendAll(device: Device, texts: string[]): Promise<void> {
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

export const bubbleTexts = (device: Device) =>
  device.page.locator('.panel-msgs .msg-row .msg-text').allInnerTexts();

const escapeRegExp = (text: string) => text.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const exactly = (text: string) => new RegExp(`^${escapeRegExp(text)}$`);

// The message rows whose bubble text is exactly `text` (a reply's quote and
// the edited badge sit outside it).
export const rowOf = (device: Device, text: string, state = '') =>
  device.page
    .locator(`.panel-msgs .msg-row${state}`)
    .filter({ has: device.page.locator('.msg-text', { hasText: exactly(text) }) });

// Opens a message's action menu and clicks one of its items; a rebuilt
// panel closes the menu, so it is opened again until the click lands.
export async function chooseAction(device: Device, text: string, item: string): Promise<void> {
  const row = rowOf(device, text);
  await expect(async () => {
    await row.click({ button: 'right' });
    await device.page.locator('.msg-action-menu button', { hasText: item }).first().click({ timeout: 2_000 });
  }).toPass({ timeout: 30_000 });
}

export async function openMenuItem(device: Device, action: string): Promise<void> {
  await device.page.click('#menu-btn');
  await device.page.locator(`#menu [data-action="${action}"]`).click();
}

export const toast = (device: Device, text: string) => device.page.locator('#toast-root .toast', { hasText: text });

export function expectNoErrors(...devices: Device[]): void {
  for (const device of devices) expect(device.errors, `errors on @${device.handle}`).toEqual([]);
}

export async function closeAll(...devices: Array<Device | undefined>): Promise<void> {
  for (const device of devices) await device?.context.close();
}
