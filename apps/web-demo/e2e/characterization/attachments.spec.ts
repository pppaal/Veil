import { expect, test } from '@playwright/test';

import { closeAll, expectNoErrors, register, relay, stamp, startChat, toast, type Device } from './support';

// Attachments are sealed in the browser and uploaded as opaque blobs; the
// key travels only inside the end-to-end encrypted message. Each round trip
// below ends in the peer's browser decoding what it downloaded.

const PNG = Buffer.from(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
  'base64',
);
const NOTES = 'veil notes\n';

test.describe.configure({ mode: 'serial' });

test.describe('attachments', () => {
  const id = stamp();
  let alice: Device;
  let bob: Device;

  test.beforeAll(async ({ browser }) => {
    await relay('/__test/reset');
    alice = await register(browser, `aalice${id}`);
    bob = await register(browser, `abob${id}`);
    await startChat(alice, bob);
  });

  test.afterAll(async () => {
    await closeAll(alice, bob);
  });

  test('an image is previewed, sent and shown decrypted on both sides', async () => {
    const { page } = alice;
    const [chooser] = await Promise.all([
      page.waitForEvent('filechooser'),
      page.locator('.panel-input .image-btn:not(.file-btn)').click(),
    ]);
    await chooser.setFiles({ name: 'dot.png', mimeType: 'image/png', buffer: PNG });
    const preview = page.locator('.image-confirm[role="dialog"]');
    await expect(preview).toContainText('Send this image?');
    await expect(preview).toContainText(`dot.png · ${PNG.length} B`);
    await preview.locator('button', { hasText: 'Send' }).click();
    await expect(preview).toHaveCount(0);

    const own = page.locator('.msg-row.me img.msg-inline-image');
    await expect(own).toHaveAttribute('src', /^blob:/);
    await expect(page.locator('.msg-row.me .msg.pending')).toHaveCount(0, { timeout: 10_000 });

    const received = bob.page.locator('.msg-row.them img.msg-inline-image');
    await expect(received).toHaveAttribute('src', /^blob:/, { timeout: 15_000 });
    await expect.poll(() => received.evaluate((image: HTMLImageElement) => image.naturalWidth)).toBe(1);
    await expect(bob.page.locator('.conv-item', { hasText: `@${alice.handle}` }).locator('.conv-preview')).toHaveText('Image');

    await received.click();
    const zoom = bob.page.locator('.image-zoom-backdrop:not([role]) img');
    await expect(zoom).toHaveAttribute('src', /^blob:/);
    await zoom.click();
    await expect(bob.page.locator('.image-zoom-backdrop')).toHaveCount(0);
    expectNoErrors(alice, bob);
  });

  test('a file is sent as a chip and downloads with its bytes', async () => {
    const { page } = alice;
    const [chooser] = await Promise.all([
      page.waitForEvent('filechooser'),
      page.locator('.panel-input .file-btn').click(),
    ]);
    await chooser.setFiles({ name: 'notes.txt', mimeType: 'text/plain', buffer: Buffer.from(NOTES) });
    const own = page.locator('.msg-row.me .msg-file-chip');
    await expect(own.locator('.msg-file-chip-name')).toHaveText('notes.txt');
    // A file card: the name, then the type and size.
    await expect(own.locator('.msg-file-chip-size')).toHaveText(`TXT · ${NOTES.length} B`);
    await expect(own).toHaveAttribute('title', 'Download');
    await expect(page.locator('.msg-row.me .msg.pending')).toHaveCount(0, { timeout: 10_000 });

    const chip = bob.page.locator('.msg-row.them .msg-file-chip');
    await expect(chip.locator('.msg-file-chip-name')).toHaveText('notes.txt', { timeout: 15_000 });
    const [download] = await Promise.all([bob.page.waitForEvent('download'), chip.click()]);
    await expect(toast(bob, 'Downloading notes.txt…')).toBeVisible();
    expect(download.suggestedFilename()).toBe('notes.txt');
    const stream = await download.createReadStream();
    const chunks: Buffer[] = [];
    for await (const chunk of stream) chunks.push(chunk as Buffer);
    expect(Buffer.concat(chunks).toString('utf8')).toBe(NOTES);
    expectNoErrors(alice, bob);
  });

  test('an image dropped on the composer asks before it is sent', async () => {
    const { page } = alice;
    const drop = (name: string, type: string) =>
      page.evaluate(
        ({ fileName, mimeType, bytes }) => {
          const transfer = new DataTransfer();
          transfer.items.add(new File([new Uint8Array(bytes)], fileName, { type: mimeType }));
          const target = document.querySelector('.panel-input') as HTMLElement;
          target.dispatchEvent(new DragEvent('dragover', { bubbles: true, cancelable: true, dataTransfer: transfer }));
          const marked = target.classList.contains('drag-over');
          target.dispatchEvent(new DragEvent('drop', { bubbles: true, cancelable: true, dataTransfer: transfer }));
          return { marked, after: target.classList.contains('drag-over') };
        },
        { fileName: name, mimeType: type, bytes: [...PNG] },
      );

    expect(await drop('dot.gif', 'image/gif')).toEqual({ marked: true, after: false });
    await expect(toast(alice, 'Only JPG, PNG and WebP images can be sent')).toBeVisible();

    await drop('dropped.png', 'image/png');
    const preview = page.locator('.image-confirm[role="dialog"]');
    await expect(preview).toContainText('dropped.png');
    await preview.locator('button', { hasText: 'Cancel' }).click();
    await expect(preview).toHaveCount(0);

    await drop('dropped.png', 'image/png');
    await expect(preview).toBeVisible();
    await page.keyboard.press('Escape');
    await expect(preview).toHaveCount(0);
    await expect(page.locator('.msg-row.me img.msg-inline-image')).toHaveCount(1);
    expectNoErrors(alice, bob);
  });
});
