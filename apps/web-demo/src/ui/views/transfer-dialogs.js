// The device-transfer dialogs in index.html (src/app/services/device-transfer.js).
// The old device shows the code, then the new device's fingerprint once a
// claim lands, and approves. The new device asks before replacing an
// identity stored here, shows its own fingerprint, and waits for the
// approval; until its keys are saved they are the identity's only copy, so
// they are kept in memory through any failure until a save succeeds. A
// claim whose completion the relay refused keeps its keys too, until the
// next claim (contract C-TRANSFER-RETRY): the dialog offers to try the same
// code again.

import { t } from '../../../i18n/i18n.js';
import { WEB_DEVICE_NAME } from '../../domain/web-device.js';
import { parseTransferCode } from '../../features/device-transfer.js';
import { ApiError, isAuthRejection } from '../../platform/api-client.js';
import { $ } from '../dom.js';
import { toast } from '../toast.js';

// The relay's refusals that mean the move is over: it was closed, it
// expired, or the old device can no longer approve it.
const ENDED_CODES = new Set(['transfer_session_inactive', 'transfer_session_not_found', 'transfer_session_expired']);
const hasEnded = (error) => error instanceof ApiError && ENDED_CODES.has(error.code);

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
      toast(t('transfer.old.done'), 'good');
    } else if (outcome === 'expired' || outcome === 'closed') {
      setText('transfer-old-status', t(outcome === 'expired' ? 'transfer.old.expired' : 'transfer.old.closed'));
      $('transfer-old-approve').classList.add('hidden');
    }
    // 'session-ended' and 'cancelled': the session's end or the cancel
    // button has already taken care of the screen.
  }

  async function startOld() {
    if (!store.state.me) {
      toast(t('transfer.signInFirst'), 'error');
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
          // The box under it says what to check: one line, not two.
          setText('transfer-old-status', '');
        },
        onPollError: () => setText('transfer-old-status', t('transfer.old.checkFailed')),
      });
    } catch {
      toast(t('transfer.old.startFailed'), 'error');
      return;
    }
    $('transfer-old-token').value = started.code;
    setText('transfer-old-status', t('transfer.old.waiting'));
    $('transfer-old-claim').classList.add('hidden');
    $('transfer-old-approve').classList.add('hidden');
    setText('transfer-old-cancel', t('common.cancel'));
    dialogs.open('transfer-old-dialog', 'transfer-old-copy');
    const outcome = await started.transfer.outcome;
    transfer.settled(started.transfer);
    await finishOld(outcome);
  }

  // The code, copied to paste on the new device; where the clipboard is
  // refused, the field is selected to copy by hand.
  async function copyOld() {
    const field = $('transfer-old-token');
    try {
      await navigator.clipboard.writeText(field.value);
      toast(t('transfer.codeCopied'), 'good');
    } catch {
      field.focus();
      field.select();
      toast(t('clipboard.failed'), 'error');
    }
  }

  // Approving moves the account and signs this browser out for good, so it
  // asks first.
  async function approveOld() {
    const watch = transfer.current();
    if (!watch) return;
    const ok = await confirm({
      title: t('transfer.old.confirmTitle'),
      body: t('transfer.old.confirmBody'),
      okLabel: t('transfer.old.confirmOk'),
      destructive: true,
    });
    if (!ok || transfer.current() !== watch) return;
    $('transfer-old-approve').disabled = true;
    try {
      await watch.approve();
      setText('transfer-old-status', t('transfer.old.approved'));
      $('transfer-old-approve').classList.add('hidden');
      setText('transfer-old-cancel', t('common.close'));
    } catch {
      toast(t('transfer.old.approveFailed'), 'error');
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
    $('transfer-new-name').value = WEB_DEVICE_NAME;
    $('transfer-new-token').value = '';
    setText('transfer-new-error', '');
    setText('transfer-new-status', '');
    $('transfer-new-fingerprint').classList.add('hidden');
    setText('transfer-new-claim', t('transfer.new.continue'));
    $('transfer-new-claim').disabled = false;
    incoming = null;
    dialogs.open('transfer-new-dialog', 'transfer-new-token');
  }

  // The relay refused to complete `started`. Its keys stay until the next
  // claim, unless a newer claim already replaced it.
  function stopNew(started, error) {
    if (incoming !== null && incoming !== started) return;
    incoming = { ...started, stopped: true };
    setText('transfer-new-error', hasEnded(error) ? t('transfer.new.ended') : '');
    setText('transfer-new-status', t('transfer.new.incomplete'));
    setText('transfer-new-claim', t('transfer.new.tryAgain'));
    $('transfer-new-claim').disabled = false;
  }

  // The stopped claim again, with the keys it was made with.
  function retryNew() {
    incoming = { ...incoming, stopped: false };
    $('transfer-new-claim').disabled = true;
    setText('transfer-new-error', '');
    setText('transfer-new-status', t('transfer.new.waiting'));
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
    setText('transfer-new-status', t('transfer.new.saving'));
    let cleanupError;
    try {
      ({ cleanupError } = await transfer.storeIdentity(incoming));
    } catch {
      setText('transfer-new-error', t('transfer.new.saveFailed'));
      setText('transfer-new-status', t('transfer.new.unsaved'));
      setText('transfer-new-claim', t('transfer.new.saveAgain'));
      $('transfer-new-claim').disabled = false;
      // The dialog may have been closed while /complete was in flight.
      if ($('transfer-new-dialog').classList.contains('hidden')) dialogs.open('transfer-new-dialog', 'transfer-new-claim');
      return;
    }
    if (cleanupError) toast(t('transfer.new.wipePartial'), 'error');
    incoming = null;
    dialogs.close('transfer-new-dialog');
    try {
      // /complete returns no tokens: the new device signs a normal challenge
      // with its newly trusted key.
      await session.login();
    } catch (error) {
      // The transfer went through and the identity is stored here; only the
      // first sign-in failed, so the auth screen offers Retry.
      toast(t('transfer.new.signInFailed'), 'error');
      await auth.show({ rejected: isAuthRejection(error) });
      return;
    }
    toast(t('transfer.new.done'), 'good');
    await session.enterApp();
  }

  async function awaitNew() {
    const started = incoming;
    if (!started) return;
    let completion;
    try {
      completion = await transfer.awaitCompletion(started, {
        waiting: () => incoming === started,
        onWaiting: () => setText('transfer-new-status', t('transfer.new.waiting')),
        onRetrying: () => setText('transfer-new-status', t('transfer.new.retrying')),
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
    const name = $('transfer-new-name').value.trim() || WEB_DEVICE_NAME;
    if (!code) {
      setText('transfer-new-error', t('transfer.new.empty'));
      return;
    }
    const parsed = parseTransferCode(code);
    if (!parsed) {
      setText('transfer-new-error', t('transfer.new.invalid'));
      return;
    }
    // Completing the transfer replaces the identity stored here, so ask now,
    // while backing out is still free.
    const replacesIdentity = await session.hasStoredIdentity();
    if (replacesIdentity) {
      const ok = await confirm({
        title: t('transfer.new.replaceTitle'),
        body: t('transfer.new.replaceBody'),
        okLabel: t('transfer.new.replaceOk'),
        destructive: true,
      });
      if (!ok) return;
    }
    $('transfer-new-claim').disabled = true;
    setText('transfer-new-error', '');
    setText('transfer-new-status', t('transfer.new.creatingKeys'));
    try {
      const { keys, published, fingerprint } = await transfer.newIdentity();
      setText('transfer-new-fingerprint-text', fingerprint);
      $('transfer-new-fingerprint').classList.remove('hidden');
      setText('transfer-new-status', t('transfer.new.contacting'));
      const claimId = await transfer.claim(parsed, { name, keys, published });
      incoming = { ...parsed, claimId, keys, replacesIdentity };
      setText('transfer-new-status', t('transfer.new.waiting'));
      awaitNew();
    } catch (error) {
      setText('transfer-new-status', '');
      setText('transfer-new-error', t(hasEnded(error) ? 'transfer.new.ended' : 'transfer.new.claimFailed'));
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
      $('transfer-old-copy').addEventListener('click', copyOld);
      $('transfer-old-approve').addEventListener('click', approveOld);
      $('transfer-new-btn').addEventListener('click', openNew);
      $('transfer-new-cancel').addEventListener('click', cancelNew);
      $('transfer-new-claim').addEventListener('click', primaryNew);
      // Another code in the field makes the button a new claim again.
      $('transfer-new-token').addEventListener('input', () => {
        if (incoming?.stopped) setText('transfer-new-claim', t(isStoppedCode() ? 'transfer.new.tryAgain' : 'transfer.new.continue'));
      });
    },
  };
}
