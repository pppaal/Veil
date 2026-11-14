import { expect, test } from '@playwright/test';

import { closeAll, expectNoErrors, openMenuItem, register, relay, reload, stamp, toast, type Device } from './support';

// A KakaoTalk export is parsed in the browser and kept on this device as a
// read-only archive in the sidebar; nothing of it is sent anywhere.

const EXPORT = [
  '[홍길동] [2024. 3. 15. 오후 2:34] 안녕하세요',
  '[김철수] [2024. 3. 15. 오후 2:35] 네 반갑습니다',
].join('\n');

test.describe('KakaoTalk import', () => {
  let device: Device;

  test.beforeAll(async ({ browser }) => {
    await relay('/__test/reset');
    device = await register(browser, `kakao${stamp()}`);
  });

  test.afterAll(async () => {
    await closeAll(device);
  });

  test('an export becomes a read-only archive in the sidebar', async () => {
    const { page } = device;
    const sent: string[] = [];
    page.on('request', (request) => sent.push(`${request.url()} ${request.postData() ?? ''}`));
    await openMenuItem(device, 'kakao-import');
    const dialog = page.locator('.dialog', { hasText: '📥 카카오톡 채팅 가져오기' });
    await expect(dialog.locator('#kakao-confirm')).toBeDisabled();
    await dialog.locator('#kakao-file').setInputFiles({ name: 'notes.pdf', mimeType: 'application/pdf', buffer: Buffer.from('%PDF') });
    await expect(dialog.locator('#kakao-error')).toHaveText('.txt 파일만 지원합니다.');
    await dialog.locator('#kakao-file').setInputFiles({ name: 'family.txt', mimeType: 'text/plain', buffer: Buffer.from(EXPORT) });
    await expect(dialog.locator('#kakao-preview')).toBeVisible();
    await expect(dialog.locator('.kakao-import-summary')).toHaveText('2 개 메시지2 명 참여 (홍길동, 김철수)');
    await dialog.locator('#kakao-confirm').click();
    await expect(toast(device, '아카이브로 저장됨')).toBeVisible();
    await expect(dialog).toHaveCount(0);

    const row = page.locator('#conv-list .conv-item', { hasText: 'family' });
    await expect(page.locator('#conv-list [data-kakao-section]')).toHaveText('카카오 아카이브');
    await expect(row).toContainText('📥family');
    await expect(row).toContainText('2 메시지 · 읽기 전용');
    await row.click();
    const panel = page.locator('#panels .panel');
    await expect(panel.locator('.panel-title .name')).toHaveText('📥 family');
    await expect(panel.locator('.kakao-archive-banner')).toHaveText('📥 카카오톡 아카이브 — 답장 / 전송 불가. 이 브라우저에만 저장됨.');
    await expect(panel.locator('.msg-text')).toHaveText(['안녕하세요', '네 반갑습니다']);
    await expect(panel.locator('.group-meta')).toHaveText(['홍길동', '김철수']);
    await expect(panel.locator('.panel-input')).toHaveCount(0);
    await expect(panel.locator('.mute-toggle')).toHaveCount(0);
    expect(sent.filter((request) => /family|홍길동|안녕하세요/.test(request))).toEqual([]);

    await reload(device);
    await expect(page.locator('#conv-list .conv-item', { hasText: 'family' })).toContainText('2 메시지 · 읽기 전용');
    expectNoErrors(device);
  });
});
