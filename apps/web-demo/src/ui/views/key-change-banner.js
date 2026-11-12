// The banner over a conversation whose peer presents an identity key the
// pins do not admit. What that key sent stays locked until the user accepts
// it or declines it; a contact they had verified has to be verified again by
// comparing the new safety number, and so does a device of theirs that was
// never verified. The conversation keeps sending to the identity its session
// sends to while the pins admit it (src/features/secure-messaging.js).

import { t } from '../../../i18n/i18n.js';
import { shownHandle } from '../../domain/handles.js';
import { HoldReason } from '../../domain/peer-bindings.js';
import { el } from '../dom.js';
import { toast } from '../toast.js';

// What a held conversation's banner, its confirmation, its frozen composer
// and its conversation row say, by src/domain/peer-bindings.js HoldReason.
const HOLD_TEXT = {
  [HoldReason.OTHER_ACCOUNT]: {
    banner: 'accountConflict.banner',
    confirmTitle: 'accountConflict.confirmTitle',
    confirmBody: 'accountConflict.confirmBody',
    composerFrozen: 'accountConflict.composerFrozen',
    sidebar: 'accountConflict.sidebar',
  },
  [HoldReason.UNISSUED_HANDLE]: {
    banner: 'unissuedHandle.banner',
    confirmTitle: 'unissuedHandle.confirmTitle',
    confirmBody: 'unissuedHandle.confirmBody',
    composerFrozen: 'unissuedHandle.composerFrozen',
    sidebar: 'unissuedHandle.sidebar',
  },
};

// The i18n key of `part` ('banner', 'confirmTitle', 'confirmBody',
// 'composerFrozen', 'sidebar') for a hold.
export const holdTextKey = (hold, part) => (HOLD_TEXT[hold.reason] ?? HOLD_TEXT[HoldReason.OTHER_ACCOUNT])[part];

// identityTrust: src/app/services/identity-trust.js; safetyDialog:
// src/ui/views/safety-dialog.js; confirm: src/ui/confirm.js.
export function createKeyChangeBanner({ identityTrust, safetyDialog, confirm }) {
  // Declines the change pending when the banner was clicked.
  async function decline(convId, peer) {
    const reviewed = identityTrust.pendingChange(peer.userId);
    if (!reviewed) return;
    const ok = await confirm({
      title: t('keyChange.declineTitle', { handle: shownHandle(peer.handle) }),
      body: t('keyChange.declineBody', { handle: shownHandle(peer.handle) }),
      okLabel: t('keyChange.decline'),
    });
    if (!ok) return;
    const outcome = await identityTrust.decline(convId, peer, reviewed);
    if (outcome === 'session-key') toast(t('keyChange.declineSessionKey', { handle: shownHandle(peer.handle) }), 'error');
    else if (outcome === 'superseded') toast(t('keyChange.superseded', { handle: shownHandle(peer.handle) }), 'error');
  }

  // Accepts the change pending when the banner was clicked, never one that
  // replaced it while the confirmation was open.
  async function accept(convId, peer) {
    const reviewed = identityTrust.pendingChange(peer.userId);
    if (!reviewed) return;
    const ok = await confirm({
      title: t('keyChange.confirmTitle', { handle: shownHandle(peer.handle) }),
      body: t('keyChange.confirmBody', { handle: shownHandle(peer.handle) }),
      okLabel: t('keyChange.accept'),
      destructive: true,
    });
    if (!ok) return;
    let outcome;
    try {
      outcome = await identityTrust.accept(peer, reviewed);
    } catch (error) {
      toast('키 수락 실패: ' + error.message, 'error');
      return;
    }
    if (outcome === 'accepted') await identityTrust.reopenLockedMessages(peer.userId);
    else if (outcome === 'superseded') toast(t('keyChange.superseded', { handle: shownHandle(peer.handle) }), 'error');
    else if (outcome === 'reverify') await safetyDialog.open(convId, peer);
  }

  async function acknowledgeAccount(convId, peer, hold) {
    const ok = await confirm({
      title: t(holdTextKey(hold, 'confirmTitle'), { handle: shownHandle(peer.handle) }),
      body: t(holdTextKey(hold, 'confirmBody'), { handle: shownHandle(peer.handle) }),
      okLabel: t('accountConflict.confirm'),
      destructive: true,
    });
    if (!ok) return;
    try {
      await identityTrust.acknowledgeAccount(convId);
    } catch (error) {
      toast(t('accountConflict.failed', { error: error.message }), 'error');
    }
  }

  return {
    // Over a conversation held for the handle it is listed under
    // (src/domain/peer-bindings.js hold): one this device knows under
    // another account, or one no honest server issues. Nothing is opened or
    // sent there until the user chooses to talk to this account
    // (src/app/services/identity-trust.js acknowledgeAccount).
    renderHold(convId, peer, hold) {
      return el('div', { class: `key-change-banner account-conflict-banner ${hold.reason}`, role: 'alert' }, [
        el('div', { class: 'key-change-text' }, [t(holdTextKey(hold, 'banner'), { handle: shownHandle(peer.handle) })]),
        el('button', {
          class: 'btn btn-secondary btn-compact',
          onclick: () => acknowledgeAccount(convId, peer, hold),
        }, [t('accountConflict.acknowledge')]),
      ]);
    },

    render(convId, peer) {
      const { textKey, needsComparison } = identityTrust.bannerFor(peer);
      return el('div', { class: 'key-change-banner', role: 'alert' }, [
        el('div', { class: 'key-change-text' }, [t(textKey, { handle: shownHandle(peer.handle) })]),
        el('button', { class: 'btn btn-ghost btn-compact key-change-decline', onclick: () => decline(convId, peer) }, [t('keyChange.decline')]),
        el('button', {
          class: 'btn btn-secondary btn-compact',
          onclick: () => (needsComparison ? safetyDialog.open(convId, peer) : accept(convId, peer)),
        }, [t(needsComparison ? 'safety.compare' : 'keyChange.review')]),
      ]);
    },
  };
}
