// The banner over a conversation whose peer presents an identity key the
// pins do not admit. Sending stays frozen until the user accepts the new key
// or declines it; a contact they had verified has to be verified again by
// comparing the new safety number, and so does a device of theirs that was
// never verified.

import { t } from '../../../i18n/i18n.js';
import { el } from '../dom.js';
import { toast } from '../toast.js';

// identityTrust: src/app/services/identity-trust.js; safetyDialog:
// src/ui/views/safety-dialog.js; confirm: src/ui/confirm.js.
export function createKeyChangeBanner({ identityTrust, safetyDialog, confirm }) {
  // Declines the change pending when the banner was clicked.
  async function decline(convId, peer) {
    const reviewed = identityTrust.pendingChange(peer.userId);
    if (!reviewed) return;
    const ok = await confirm({
      title: t('keyChange.declineTitle', { handle: peer.handle }),
      body: t('keyChange.declineBody', { handle: peer.handle }),
      okLabel: t('keyChange.decline'),
    });
    if (!ok) return;
    const outcome = await identityTrust.decline(convId, peer, reviewed);
    if (outcome === 'session-key') toast(t('keyChange.declineSessionKey', { handle: peer.handle }), 'error');
    else if (outcome === 'superseded') toast(t('keyChange.superseded', { handle: peer.handle }), 'error');
  }

  // Accepts the change pending when the banner was clicked, never one that
  // replaced it while the confirmation was open.
  async function accept(convId, peer) {
    const reviewed = identityTrust.pendingChange(peer.userId);
    if (!reviewed) return;
    const ok = await confirm({
      title: t('keyChange.confirmTitle', { handle: peer.handle }),
      body: t('keyChange.confirmBody', { handle: peer.handle }),
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
    else if (outcome === 'superseded') toast(t('keyChange.superseded', { handle: peer.handle }), 'error');
    else if (outcome === 'reverify') await safetyDialog.open(convId, peer);
  }

  return {
    render(convId, peer) {
      const { textKey, needsComparison } = identityTrust.bannerFor(peer);
      return el('div', { class: 'key-change-banner', role: 'alert' }, [
        el('div', { class: 'key-change-text' }, [t(textKey, { handle: peer.handle })]),
        el('button', { class: 'btn btn-ghost btn-compact key-change-decline', onclick: () => decline(convId, peer) }, [t('keyChange.decline')]),
        el('button', {
          class: 'btn btn-secondary btn-compact',
          onclick: () => (needsComparison ? safetyDialog.open(convId, peer) : accept(convId, peer)),
        }, [t(needsComparison ? 'safety.compare' : 'keyChange.review')]),
      ]);
    },
  };
}
