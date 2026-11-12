import { expect, test, type Page } from '@playwright/test';

import {
  bubbleTexts,
  closeAll,
  expectNoErrors,
  register,
  relay,
  send,
  stamp,
  startChat,
  toast,
  type Device,
} from './support';

// Where trust decisions reach the user: the safety-number dialog, and the
// banner a key the pins do not admit raises, with its decline and accept
// paths, for a contact that was verified and one that was not.

test.describe.configure({ mode: 'serial' });

async function openSafetyDialog(page: Page) {
  await page.locator('.panel-header .icon-btn', { hasText: '🛡' }).click();
  const dialog = page.locator('#safety-dialog');
  await expect(dialog).toBeVisible();
  return dialog;
}

test.describe('a contact verified by safety number', () => {
  const id = stamp();
  let alice: Device;
  let bob: Device;

  test.beforeAll(async ({ browser }) => {
    await relay('/__test/reset');
    alice = await register(browser, `talice${id}`);
    bob = await register(browser, `tbob${id}`);
    await startChat(alice, bob);
    await send(alice, 'first contact');
    await expect.poll(() => bubbleTexts(bob), { timeout: 15_000 }).toEqual(['first contact']);
    await send(bob, 'answered');
    await expect.poll(() => bubbleTexts(alice), { timeout: 15_000 }).toEqual(['first contact', 'answered']);
  });

  test.afterAll(async () => {
    await closeAll(alice, bob);
  });

  test('compares codes and marks the key verified', async () => {
    const bobDialog = await openSafetyDialog(bob.page);
    const bobCode = await bobDialog.locator('.safety-code').inputValue();
    const bobNumber = (await bobDialog.locator('#safety-number').innerText()).trim();
    await bob.page.keyboard.press('Escape');
    await expect(bobDialog).toHaveCount(0);

    const dialog = await openSafetyDialog(alice.page);
    await expect(dialog.locator('#safety-title')).toHaveText(`@${bob.handle} 와의 안전 번호`);
    await expect(dialog.locator('#safety-their-code')).toBeFocused();
    expect((await dialog.locator('#safety-number').innerText()).trim()).toBe(bobNumber);
    expect(bobNumber.replace(/\s/g, '')).toMatch(/^\d{60}$/);
    await expect(dialog).not.toContainText('이 키는 확인을 마쳤어요.');

    await dialog.locator('#safety-their-code').fill('not their code');
    await dialog.locator('button', { hasText: '코드 비교' }).click();
    await expect(dialog.locator('.dialog-error')).toHaveText('코드가 일치하지 않아요. 이 키를 신뢰하지 마세요.');
    await dialog.locator('#safety-their-code').fill(bobCode);
    await dialog.locator('button', { hasText: '코드 비교' }).click();
    await expect(dialog).toHaveCount(0);
    await expect(toast(alice, `@${bob.handle} 확인 완료`)).toBeVisible();

    const again = await openSafetyDialog(alice.page);
    await expect(again).toContainText('이 키는 확인을 마쳤어요.');
    await again.locator('button', { hasText: '취소' }).click();
    await expect(again).toHaveCount(0);
    expectNoErrors(alice, bob);
  });

  test('a new key of a verified contact is accepted only by comparing it', async () => {
    await relay('/__test/impersonate', { victim: bob.handle, target: alice.handle, text: 'relay as verified bob' });
    const { page } = alice;
    const banner = page.locator('.key-change-banner');
    await expect(banner).toBeVisible({ timeout: 15_000 });
    await expect(banner.locator('.key-change-text')).toHaveText(
      `@${bob.handle} 의 보안 키가 바뀌었어요. 확인했던 상대예요: 다시 보내기 전에 새 안전 번호를 비교하세요.`,
    );
    await expect(page.locator('.panel-input textarea')).toBeDisabled();
    await expect(page.locator('.panel-input textarea')).toHaveAttribute('placeholder', '보안 키 변경을 확인하기 전까지 전송이 중지됨');
    await expect(page.locator('.panel-msgs .msg-row.them').last()).toContainText('🔒 보안 키 변경 — 확인 필요');

    await banner.locator('button', { hasText: '안전 번호 비교' }).click();
    const dialog = page.locator('#safety-dialog');
    await expect(dialog).toContainText('아직 수락하지 않은 새 키예요. 상대와 비교한 뒤에만 확인하세요.');
    await dialog.locator('button', { hasText: '확인됨으로 표시' }).click();
    await expect(dialog).toHaveCount(0);
    await expect(banner).toHaveCount(0);
    await expect.poll(() => bubbleTexts(alice), { timeout: 15_000 }).toEqual(['first contact', 'answered', 'relay as verified bob']);
    await expect(page.locator('.panel-input textarea')).toBeEnabled();
    expectNoErrors(alice, bob);
  });
});

test.describe('a contact never verified', () => {
  const id = stamp();
  let carol: Device;
  let dave: Device;

  test.beforeAll(async ({ browser }) => {
    await relay('/__test/reset');
    carol = await register(browser, `tcarol${id}`);
    dave = await register(browser, `tdave${id}`);
    await startChat(carol, dave);
    await send(carol, 'hello dave');
    await expect.poll(() => bubbleTexts(dave), { timeout: 15_000 }).toEqual(['hello dave']);
    await send(dave, 'hello carol');
    await expect.poll(() => bubbleTexts(carol), { timeout: 15_000 }).toEqual(['hello dave', 'hello carol']);
  });

  test.afterAll(async () => {
    await closeAll(carol, dave);
  });

  test('declining a swapped key keeps it locked and the chat sending', async () => {
    await relay('/__test/impersonate', { victim: dave.handle, target: carol.handle, text: 'relay try one' });
    const { page } = carol;
    const banner = page.locator('.key-change-banner');
    await expect(banner).toBeVisible({ timeout: 15_000 });
    await expect(banner.locator('.key-change-text')).toHaveText(
      `@${dave.handle} 의 보안 키가 바뀌었어요. 확인하기 전까지 이 대화에서는 보낼 수 없어요.`,
    );
    await expect(page.locator('.conv-item', { hasText: `@${dave.handle}` }).locator('.conv-preview')).toHaveText('⚠️ 보안 키 변경됨');
    await expect(page.locator('.send-btn')).toBeDisabled();

    await banner.locator('.key-change-decline').click();
    await expect(page.locator('#confirm-title')).toHaveText(`@${dave.handle} 의 이 키를 거절할까요?`);
    await page.click('#confirm-cancel');
    await expect(banner).toBeVisible();
    await banner.locator('.key-change-decline').click();
    await page.click('#confirm-ok');
    await expect(banner).toHaveCount(0);
    await expect(page.locator('.panel-msgs .msg-row.them').last()).toContainText('🔒');
    await send(carol, 'still talking to dave');
    await expect.poll(() => bubbleTexts(dave), { timeout: 15_000 }).toContain('still talking to dave');
    expectNoErrors(carol, dave);
  });

  test('accepting a swapped key opens what it sent', async () => {
    await relay('/__test/impersonate', { victim: dave.handle, target: carol.handle, text: 'relay try two' });
    const { page } = carol;
    const banner = page.locator('.key-change-banner');
    await expect(banner).toBeVisible({ timeout: 15_000 });
    await banner.locator('button', { hasText: '확인' }).click();
    await expect(page.locator('#confirm-title')).toHaveText(`@${dave.handle} 의 새 키를 수락할까요?`);
    await expect(page.locator('#confirm-ok')).toHaveText('새 키 수락');
    await page.click('#confirm-ok');
    await expect(banner).toHaveCount(0);
    await expect.poll(() => bubbleTexts(carol), { timeout: 15_000 }).toContain('relay try two');
    expect(await bubbleTexts(carol)).not.toContain('relay try one');
    await expect(page.locator('.panel-input textarea')).toBeEnabled();
    expectNoErrors(carol, dave);
  });
});
