// The safety-number dialog of a direct conversation. The user compares the
// number in person or over a call, or pastes the verification code the
// peer's screen shows; what they mark verified is exactly the key the
// dialog showed (src/app/services/identity-trust.js).

import { t } from '../../../i18n/i18n.js';
import { trapFocus } from '../confirm.js';
import { $, el } from '../dom.js';
import { toast } from '../toast.js';

const DIALOG_ID = 'safety-dialog';

// identityTrust: src/app/services/identity-trust.js; dialogs: src/ui/dialogs.js.
export function createSafetyDialog({ identityTrust, dialogs }) {
  return {
    async open(convId, peer) {
      const safety = await identityTrust.safetyNumberFor(convId, peer);
      if (safety.status === 'not-signed-in') {
        toast(t('safety.notSignedIn'), 'error');
        return;
      }
      if (safety.status === 'no-key') {
        toast(t('safety.noKey', { handle: peer.handle }), 'error');
        return;
      }
      const codeInput = el('input', {
        id: 'safety-their-code',
        type: 'text',
        placeholder: t('safety.pastePlaceholder'),
        autocomplete: 'off',
        spellcheck: 'false',
      });
      const result = el('div', { class: 'dialog-error', role: 'status', 'aria-live': 'polite' });
      let backdrop = null;
      const close = () => {
        dialogs.close(DIALOG_ID);
        backdrop.remove();
      };
      const markVerified = async () => {
        try {
          await identityTrust.markVerified(peer, safety.remoteKey);
        } catch (error) {
          result.textContent = t('safety.verifyFailed', { error: error.message });
          return;
        }
        toast(t('safety.verified', { handle: peer.handle }), 'good');
        close();
        await identityTrust.reopenLockedMessages(peer.userId);
      };
      const compare = async () => {
        if (safety.matches(codeInput.value.trim())) await markVerified();
        else result.textContent = t('safety.mismatch');
      };
      backdrop = el('div', { class: 'dialog-backdrop hidden', id: DIALOG_ID, role: 'presentation' }, [
        el('div', {
          class: 'dialog',
          role: 'dialog',
          'aria-modal': 'true',
          'aria-labelledby': 'safety-title',
          style: 'width:420px;max-width:92vw',
        }, [
          el('div', { class: 'dialog-title', id: 'safety-title' }, [t('safety.title', { handle: peer.handle })]),
          safety.pendingNoteKey ? el('div', { class: 'key-change-text', role: 'alert' }, [t(safety.pendingNoteKey, { handle: peer.handle })]) : null,
          safety.remoteKey.verified ? el('div', { class: 'dialog-sub' }, [t('safety.alreadyVerified')]) : null,
          el('div', { class: 'safety-number', id: 'safety-number' }, [safety.number]),
          el('div', { class: 'dialog-sub' }, [t('safety.explain', { handle: peer.handle })]),
          el('div', { class: 'field-label' }, [t('safety.yourCode')]),
          el('textarea', { readonly: 'readonly', rows: '3', class: 'safety-code' }, [safety.code]),
          el('div', { class: 'field-label' }, [t('safety.theirCode')]),
          codeInput,
          result,
          el('div', { class: 'dialog-actions' }, [
            el('button', { class: 'btn btn-ghost', onclick: close }, [t('common.cancel')]),
            el('button', { class: 'btn btn-secondary', onclick: compare }, [t('safety.compareCode')]),
            el('button', { class: 'btn btn-primary', onclick: markVerified }, [t('safety.markVerified')]),
          ]),
        ]),
      ]);
      backdrop.addEventListener('click', (event) => {
        if (event.target === backdrop) close();
      });
      backdrop.addEventListener('keydown', (event) => {
        if (event.key === 'Escape') {
          event.preventDefault();
          close();
        } else {
          trapFocus(DIALOG_ID, event);
        }
      });
      // One safety dialog at a time: a second click while the first was
      // being prepared opens nothing.
      if ($(DIALOG_ID)) return;
      document.body.appendChild(backdrop);
      dialogs.open(DIALOG_ID, 'safety-their-code');
    },
  };
}
