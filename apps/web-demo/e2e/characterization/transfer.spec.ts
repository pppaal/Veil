import { expect, test } from '@playwright/test';

import {
  bubbleTexts,
  closeAll,
  expectNoErrors,
  openChatWith,
  openMenuItem,
  register,
  relay,
  send,
  stamp,
  startChat,
  toast,
  type Device,
} from './support';

// Device transfer from an old browser to a new one that already holds an
// identity of its own: the new side asks before replacing it, both sides
// show the same fingerprint, the old side approves, and afterwards the
// handle lives only on the new browser.

test.describe.configure({ mode: 'serial' });

test.describe('device transfer', () => {
  const id = stamp();
  let alice: Device;
  let bob: Device;
  let spare: Device;

  test.beforeAll(async ({ browser }) => {
    await relay('/__test/reset');
    alice = await register(browser, `xalice${id}`);
    bob = await register(browser, `xbob${id}`);
    // A browser whose own identity the relay has revoked: it sits on the
    // auth screen with its keys still stored.
    spare = await register(browser, `xspare${id}`);
    await relay('/__test/revoke', { handle: spare.handle });
    await expect(spare.page.locator('#restore-rejected')).toBeVisible({ timeout: 15_000 });
    await startChat(alice, bob);
    await send(alice, 'before the move');
    await expect.poll(() => bubbleTexts(bob), { timeout: 15_000 }).toEqual(['before the move']);
  });

  test.afterAll(async () => {
    await closeAll(alice, bob, spare);
  });

  test('moves the handle to a browser that asks before replacing its identity', async () => {
    await openMenuItem(alice, 'transfer-start');
    const oldDialog = alice.page.locator('#transfer-old-dialog');
    await expect(oldDialog).toBeVisible();
    await expect(alice.page.locator('#transfer-old-status')).toHaveText('코드 복사 후 새 기기에 붙여넣기 — 새 기기 클레임 대기 중…');
    await expect(alice.page.locator('#transfer-old-approve')).toBeHidden();
    const code = await alice.page.locator('#transfer-old-token').inputValue();
    expect(code).toMatch(/^[A-Za-z0-9+/]+$/);

    const { page } = spare;
    await page.click('#transfer-new-btn');
    const newDialog = page.locator('#transfer-new-dialog');
    await expect(newDialog).toBeVisible();
    await expect(page.locator('#transfer-new-name')).toHaveValue(/^web-/);
    await page.click('#transfer-new-claim');
    await expect(page.locator('#transfer-new-error')).toHaveText('코드가 필요합니다');
    await page.fill('#transfer-new-token', 'not a code');
    await page.click('#transfer-new-claim');
    await expect(page.locator('#transfer-new-error')).toHaveText('코드 형식 오류');

    await page.fill('#transfer-new-token', code);
    await page.click('#transfer-new-claim');
    await expect(page.locator('#confirm-title')).toHaveText('기존 신원 교체');
    await page.click('#confirm-cancel');
    await expect(page.locator('#transfer-new-fingerprint')).toBeHidden();
    await page.click('#transfer-new-claim');
    await page.click('#confirm-ok');

    const fingerprint = page.locator('#transfer-new-fingerprint-text');
    await expect(fingerprint).toHaveText(/^([0-9a-f]{4} ){15}[0-9a-f]{4}$/);
    await expect(page.locator('#transfer-new-status')).toHaveText('이전 기기에서 승인 대기 중…');
    await expect(alice.page.locator('#transfer-old-fingerprint')).toHaveText(await fingerprint.innerText(), { timeout: 10_000 });
    await expect(alice.page.locator('#transfer-old-status')).toHaveText('지문 확인 후 승인하세요.');
    await alice.page.click('#transfer-old-approve');

    await expect(page.locator('#app')).toBeVisible({ timeout: 15_000 });
    await expect(toast(spare, '이전 완료 — 새 기기로 들어왔습니다')).toBeVisible();
    await expect(newDialog).toBeHidden();
    await expect(page.locator('#sidebar-me')).toContainText(`@${alice.handle}`);

    await expect(alice.page.locator('#auth-screen')).toBeVisible({ timeout: 15_000 });
    await expect(toast(alice, '이전 완료 — 이 기기의 키를 삭제했습니다')).toBeVisible();
    await expect(alice.page.locator('#restore-row')).toBeHidden();
    await expect(oldDialog).toBeHidden();

    // The replaced identity left nothing behind on the new browser.
    const kept = await page.evaluate(() => Object.keys(localStorage).filter((key) => key.startsWith('veil-')));
    expect(kept).toEqual([]);
    await page.reload();
    await expect(page.locator('#app')).toBeVisible();
    await expect(page.locator('#sidebar-me')).toContainText(`@${alice.handle}`);
    expectNoErrors(alice, bob, spare);
  });

  test('the moved handle keeps the conversation going from its new keys', async () => {
    const moved: Device = { ...spare, handle: alice.handle };
    await openChatWith(moved, bob);
    await send(moved, 'from the new browser');
    // The peer sees a new key for the same handle and reviews it first.
    await expect(bob.page.locator('.key-change-banner')).toBeVisible({ timeout: 15_000 });
    await bob.page.locator('.key-change-banner button', { hasText: '확인' }).click();
    await bob.page.click('#confirm-ok');
    await expect.poll(() => bubbleTexts(bob), { timeout: 15_000 }).toEqual(['before the move', 'from the new browser']);
    expectNoErrors(bob, spare);
  });
});
