// The device-transfer dialogs in index.html (src/app/services/device-transfer.js).
// The old device shows the code, then the new device's fingerprint once a
// claim lands, and approves. The new device asks before replacing an
// identity stored here, shows its own fingerprint, and waits for the
// approval; until its keys are saved they are the identity's only copy, so
// they are kept in memory through any failure until a save succeeds. A
// claim whose completion the relay refused keeps its keys too, until the
// next claim (contract C-TRANSFER-RETRY): the dialog offers to try the same
// code again.

import { parseTransferCode } from '../../features/device-transfer.js';
import { isAuthRejection } from '../../platform/api-client.js';
import { $ } from '../dom.js';
import { toast } from '../toast.js';

const WAITING_FOR_APPROVAL = '이전 기기에서 승인 대기 중…';
const RETRYING = '서버 응답이 없어요 — 같은 요청으로 다시 시도 중…';

// transfer: src/app/services/device-transfer.js; session:
// src/app/services/session.js; auth: src/ui/views/auth-view.js;
// dialogs: src/ui/dialogs.js; confirm: src/ui/confirm.js.
export function createTransferDialogs({ store, transfer, session, auth, dialogs, confirm }) {
  // The new device's transfer in progress: the parsed code, claimId, keys,
  // whether it replaces a stored identity, once done its completion, and
  // `stopped` once the relay refused to complete it.
  let incoming = null;

  const setText = (id, text) => {
    $(id).textContent = text;
  };

  function closeOldDialog() {
    if (!$('transfer-old-dialog').classList.contains('hidden')) dialogs.close('transfer-old-dialog');
  }

  function stopOld() {
    transfer.stop();
    closeOldDialog();
  }

  async function finishOld(outcome) {
    if (outcome === 'completed') {
      // The handle now lives on the new device; this copy of the identity
      // is spent, so a completed transfer is one of the two ways it goes.
      closeOldDialog();
      await session.destroyIdentity();
      toast('이전 완료 — 이 기기의 키를 삭제했습니다', 'good');
    } else if (outcome === 'expired' || outcome === 'closed') {
      setText('transfer-old-status', outcome === 'expired' ? '만료되었습니다 (5분 초과). 다시 시작하세요.' : '이 이전 세션은 닫혔어요. 다시 시작하세요.');
      $('transfer-old-approve').classList.add('hidden');
    }
    // 'session-ended' and 'cancelled': the session's end or the cancel
    // button has already taken care of the screen.
  }

  async function startOld() {
    if (!store.state.me) {
      toast('로그인 후 시도하세요', 'error');
      return;
    }
    stopOld();
    let started;
    try {
      started = await transfer.start({
        onClaim: (claim) => {
          setText('transfer-old-fingerprint', claim.claimantFingerprint);
          $('transfer-old-claim').classList.remove('hidden');
          $('transfer-old-approve').classList.remove('hidden');
          setText('transfer-old-status', '지문 확인 후 승인하세요.');
        },
        onPollError: (error) => setText('transfer-old-status', '폴링 오류: ' + error.message),
      });
    } catch (error) {
      toast('이전 시작 실패: ' + error.message, 'error');
      return;
    }
    $('transfer-old-token').value = started.code;
    setText('transfer-old-status', '코드 복사 후 새 기기에 붙여넣기 — 새 기기 클레임 대기 중…');
    $('transfer-old-claim').classList.add('hidden');
    $('transfer-old-approve').classList.add('hidden');
    setText('transfer-old-cancel', '취소');
    dialogs.open('transfer-old-dialog', 'transfer-old-token');
    const outcome = await started.transfer.outcome;
    transfer.settled(started.transfer);
    await finishOld(outcome);
  }

  async function approveOld() {
    const watch = transfer.current();
    if (!watch) return;
    $('transfer-old-approve').disabled = true;
    try {
      await watch.approve();
      setText('transfer-old-status', '승인됨 — 새 기기가 완료할 때까지 대기…');
      $('transfer-old-approve').classList.add('hidden');
      setText('transfer-old-cancel', '닫기');
    } catch (error) {
      toast('승인 실패: ' + error.message, 'error');
    } finally {
      $('transfer-old-approve').disabled = false;
    }
  }

  // The server cannot call off an approved transfer, so after an approval
  // the dialog only closes and the watch runs on until the transfer ends.
  function cancelOld() {
    if (transfer.current()?.approved) closeOldDialog();
    else stopOld();
  }

  function openNew() {
    // A completed transfer whose keys are not saved yet, or a claim whose
    // completion was refused, reopens on its retry.
    if (incoming?.completion || incoming?.stopped) {
      dialogs.open('transfer-new-dialog', 'transfer-new-claim');
      return;
    }
    $('transfer-new-name').value = 'web-' + (navigator.platform || 'browser');
    $('transfer-new-token').value = '';
    setText('transfer-new-error', '');
    setText('transfer-new-status', '');
    $('transfer-new-fingerprint').classList.add('hidden');
    setText('transfer-new-claim', '클레임');
    $('transfer-new-claim').disabled = false;
    incoming = null;
    dialogs.open('transfer-new-dialog', 'transfer-new-token');
  }

  // The relay refused to complete `started`. Its keys stay until the next
  // claim, unless a newer claim already replaced it.
  function stopNew(started, error) {
    if (incoming !== null && incoming !== started) return;
    incoming = { ...started, stopped: true };
    setText('transfer-new-error', error.message);
    setText('transfer-new-status', '이전을 완료하지 못했어요. 같은 코드로 다시 시도하거나, 새 코드를 붙여넣어 다시 클레임하세요.');
    setText('transfer-new-claim', '다시 시도');
    $('transfer-new-claim').disabled = false;
  }

  // The stopped claim again, with the keys it was made with.
  function retryNew() {
    incoming = { ...incoming, stopped: false };
    $('transfer-new-claim').disabled = true;
    setText('transfer-new-error', '');
    setText('transfer-new-status', WAITING_FOR_APPROVAL);
    awaitNew();
  }

  // The code in the field is the one the stopped claim was made with.
  function isStoppedCode() {
    const parsed = parseTransferCode($('transfer-new-token').value.trim());
    return Boolean(incoming?.stopped && parsed
      && parsed.sessionId === incoming.sessionId && parsed.transferToken === incoming.transferToken);
  }

  // Runs once the transfer completed, and again from the dialog's button
  // after a failed save: the keys stay in `incoming` until stored.
  async function saveNew() {
    $('transfer-new-claim').disabled = true;
    setText('transfer-new-error', '');
    setText('transfer-new-status', '새 키 저장 중…');
    let cleanupError;
    try {
      ({ cleanupError } = await transfer.storeIdentity(incoming));
    } catch (error) {
      setText('transfer-new-error', '새 키를 저장하지 못했어요: ' + error.message);
      setText('transfer-new-status', '이전은 완료됐고 키는 이 탭에만 있어요. 탭을 닫지 말고 다시 저장하세요.');
      setText('transfer-new-claim', '다시 저장');
      $('transfer-new-claim').disabled = false;
      // The dialog may have been closed while /complete was in flight.
      if ($('transfer-new-dialog').classList.contains('hidden')) dialogs.open('transfer-new-dialog', 'transfer-new-claim');
      return;
    }
    if (cleanupError) toast('이전 신원의 데이터 일부를 지우지 못했어요: ' + cleanupError.message, 'error');
    incoming = null;
    dialogs.close('transfer-new-dialog');
    try {
      // /complete returns no tokens: the new device signs a normal challenge
      // with its newly trusted key.
      await session.login();
    } catch (error) {
      // The transfer went through and the identity is stored here; only the
      // first sign-in failed, so the auth screen offers Retry.
      toast('이전은 완료됐지만 로그인하지 못했어요: ' + error.message, 'error');
      await auth.show({ rejected: isAuthRejection(error) });
      return;
    }
    toast('이전 완료 — 새 기기로 들어왔습니다', 'good');
    await session.enterApp();
  }

  async function awaitNew() {
    const started = incoming;
    if (!started) return;
    let completion;
    try {
      completion = await transfer.awaitCompletion(started, {
        waiting: () => incoming === started,
        onWaiting: () => setText('transfer-new-status', WAITING_FOR_APPROVAL),
        onRetrying: () => setText('transfer-new-status', RETRYING),
      });
    } catch (error) {
      stopNew(started, error);
      return;
    }
    if (!completion) return;
    // Kept even if the dialog was cancelled while /complete was in flight or
    // being retried: the server has activated these keys and the old device
    // destroys its copy, so they are the identity's only copy until saveNew
    // stores them.
    incoming = { ...started, completion };
    await saveNew();
  }

  async function claimNew() {
    const code = $('transfer-new-token').value.trim();
    const name = $('transfer-new-name').value.trim() || 'VEIL';
    if (!code) {
      setText('transfer-new-error', '코드가 필요합니다');
      return;
    }
    const parsed = parseTransferCode(code);
    if (!parsed) {
      setText('transfer-new-error', '코드 형식 오류');
      return;
    }
    // Completing the transfer replaces the identity stored here, so ask now,
    // while backing out is still free.
    const replacesIdentity = await session.hasStoredIdentity();
    if (replacesIdentity) {
      const ok = await confirm({
        title: '기존 신원 교체',
        body: '이 브라우저에 저장된 신원은 이전이 완료되면 영구 삭제되고, 그 핸들로는 다시 로그인할 수 없어요.',
        okLabel: '계속',
        destructive: true,
      });
      if (!ok) return;
    }
    $('transfer-new-claim').disabled = true;
    setText('transfer-new-error', '');
    setText('transfer-new-status', '새 키 생성 중…');
    try {
      const { keys, published, fingerprint } = await transfer.newIdentity();
      setText('transfer-new-fingerprint-text', fingerprint);
      $('transfer-new-fingerprint').classList.remove('hidden');
      setText('transfer-new-status', '서버에 클레임 중…');
      const claimId = await transfer.claim(parsed, { name, keys, published });
      incoming = { ...parsed, claimId, keys, replacesIdentity };
      setText('transfer-new-status', WAITING_FOR_APPROVAL);
      awaitNew();
    } catch (error) {
      setText('transfer-new-error', error.message);
      $('transfer-new-claim').disabled = false;
    }
  }

  // Keys a completed transfer activated are never dropped, nor those of a
  // claim whose completion was refused: the dialog only closes, and opening
  // it again brings back the retry. A claim still waiting for the approval
  // stops waiting.
  function cancelNew() {
    if (!incoming?.completion && !incoming?.stopped) incoming = null;
    dialogs.close('transfer-new-dialog');
  }

  function primaryNew() {
    if (incoming?.completion) saveNew();
    else if (isStoppedCode()) retryNew();
    else claimNew();
  }

  return {
    startOld,
    stopOld,

    mount() {
      $('transfer-old-cancel').addEventListener('click', cancelOld);
      $('transfer-old-approve').addEventListener('click', approveOld);
      $('transfer-new-btn').addEventListener('click', openNew);
      $('transfer-new-cancel').addEventListener('click', cancelNew);
      $('transfer-new-claim').addEventListener('click', primaryNew);
      // Another code in the field makes the button a new claim again.
      $('transfer-new-token').addEventListener('input', () => {
        if (incoming?.stopped) setText('transfer-new-claim', isStoppedCode() ? '다시 시도' : '클레임');
      });
    },
  };
}
