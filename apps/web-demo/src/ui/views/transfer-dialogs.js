// The device-transfer dialogs in index.html (src/app/services/device-transfer.js).
// The old device shows the code, then the new device's fingerprint once a
// claim lands, and approves. The new device asks before replacing an
// identity stored here, shows its own fingerprint, and waits for the
// approval; until its keys are saved they are the identity's only copy, so
// they are kept in memory through any failure until a save succeeds. A
// claim whose completion the relay refused keeps its keys too, until the
// next claim (contract C-TRANSFER-RETRY): the dialog offers to try the same
// code again.

import { WEB_DEVICE_NAME } from '../../domain/web-device.js';
import { parseTransferCode } from '../../features/device-transfer.js';
import { isAuthRejection } from '../../platform/api-client.js';
import { $ } from '../dom.js';
import { toast } from '../toast.js';

const WAITING_FOR_APPROVAL = 'Waiting for approval on the old device…';
const RETRYING = 'No answer from the server. Trying the same request again…';
const USE_CODE = 'Use code';
const TRY_AGAIN = 'Try again';

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
      toast('Transfer complete. The keys on this device were deleted.', 'good');
    } else if (outcome === 'expired' || outcome === 'closed') {
      setText('transfer-old-status', outcome === 'expired' ? 'The code expired after 5 minutes. Start again.' : 'This transfer was closed. Start again.');
      $('transfer-old-approve').classList.add('hidden');
    }
    // 'session-ended' and 'cancelled': the session's end or the cancel
    // button has already taken care of the screen.
  }

  async function startOld() {
    if (!store.state.me) {
      toast('Sign in first', 'error');
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
          setText('transfer-old-status', 'Check the fingerprint, then approve.');
        },
        onPollError: (error) => setText('transfer-old-status', 'Could not check the server: ' + error.message),
      });
    } catch (error) {
      toast('Could not start the transfer: ' + error.message, 'error');
      return;
    }
    $('transfer-old-token').value = started.code;
    setText('transfer-old-status', 'Copy the code and paste it on the new device. Waiting for the new device…');
    $('transfer-old-claim').classList.add('hidden');
    $('transfer-old-approve').classList.add('hidden');
    setText('transfer-old-cancel', 'Cancel');
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
      setText('transfer-old-status', 'Approved. Waiting for the new device to finish…');
      $('transfer-old-approve').classList.add('hidden');
      setText('transfer-old-cancel', 'Close');
    } catch (error) {
      toast('Could not approve: ' + error.message, 'error');
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
    setText('transfer-new-claim', USE_CODE);
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
    setText('transfer-new-status', 'The transfer could not be completed. Try again with the same code, or paste a new code.');
    setText('transfer-new-claim', TRY_AGAIN);
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
    setText('transfer-new-status', 'Saving the new keys…');
    let cleanupError;
    try {
      ({ cleanupError } = await transfer.storeIdentity(incoming));
    } catch (error) {
      setText('transfer-new-error', 'Could not save the new keys: ' + error.message);
      setText('transfer-new-status', 'The transfer is complete, but the keys exist only in this tab. Do not close it. Save again.');
      setText('transfer-new-claim', 'Save again');
      $('transfer-new-claim').disabled = false;
      // The dialog may have been closed while /complete was in flight.
      if ($('transfer-new-dialog').classList.contains('hidden')) dialogs.open('transfer-new-dialog', 'transfer-new-claim');
      return;
    }
    if (cleanupError) toast('Some data of the previous account could not be deleted: ' + cleanupError.message, 'error');
    incoming = null;
    dialogs.close('transfer-new-dialog');
    try {
      // /complete returns no tokens: the new device signs a normal challenge
      // with its newly trusted key.
      await session.login();
    } catch (error) {
      // The transfer went through and the identity is stored here; only the
      // first sign-in failed, so the auth screen offers Retry.
      toast('The transfer is complete, but signing in failed: ' + error.message, 'error');
      await auth.show({ rejected: isAuthRejection(error) });
      return;
    }
    toast('Transfer complete. You are signed in on this device.', 'good');
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
    const name = $('transfer-new-name').value.trim() || WEB_DEVICE_NAME;
    if (!code) {
      setText('transfer-new-error', 'Enter the code');
      return;
    }
    const parsed = parseTransferCode(code);
    if (!parsed) {
      setText('transfer-new-error', 'This is not a valid code');
      return;
    }
    // Completing the transfer replaces the identity stored here, so ask now,
    // while backing out is still free.
    const replacesIdentity = await session.hasStoredIdentity();
    if (replacesIdentity) {
      const ok = await confirm({
        title: 'Replace the account in this browser',
        body: 'When the transfer completes, the account stored in this browser is deleted for good. You will not be able to sign in to that handle again.',
        okLabel: 'Continue',
        destructive: true,
      });
      if (!ok) return;
    }
    $('transfer-new-claim').disabled = true;
    setText('transfer-new-error', '');
    setText('transfer-new-status', 'Creating new keys…');
    try {
      const { keys, published, fingerprint } = await transfer.newIdentity();
      setText('transfer-new-fingerprint-text', fingerprint);
      $('transfer-new-fingerprint').classList.remove('hidden');
      setText('transfer-new-status', 'Contacting the server…');
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
        if (incoming?.stopped) setText('transfer-new-claim', isStoppedCode() ? TRY_AGAIN : USE_CODE);
      });
    },
  };
}
