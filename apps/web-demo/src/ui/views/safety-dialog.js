// The safety-number dialog of a direct conversation. The user compares the
// number in person or over a call, or pastes the verification code the
// peer's screen shows; what they mark verified is exactly the key the
// dialog showed (src/app/services/identity-trust.js).

import { t } from '../../../i18n/i18n.js';
import { shownHandle } from '../../domain/handles.js';
import { trapFocus } from '../confirm.js';
import { $, el, icon } from '../dom.js';
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
        toast(t('safety.noKey', { handle: shownHandle(peer.handle) }), 'error');
        return;
      }
      const codeInput = el('input', {
        id: 'safety-their-code',
        type: 'text',
        'aria-label': t('safety.theirCode'),
        placeholder: t('safety.pastePlaceholder'),
        autocomplete: 'off',
        spellcheck: 'false',
      });
      const result = el('div', { class: 'dialog-error', role: 'status', 'aria-live': 'polite' });
      let backdrop = null;
      // Set while the code to copy by hand is shown; see showCodeToCopy.
      let refitHandCopy = null;
      const close = () => {
        if (refitHandCopy) window.removeEventListener('resize', refitHandCopy);
        dialogs.close(DIALOG_ID);
        backdrop.remove();
      };
      const markVerified = async () => {
        try {
          await identityTrust.markVerified(peer, safety.remoteKey);
        } catch {
          result.textContent = t('safety.verifyFailed');
          return;
        }
        toast(t('safety.verified', { handle: shownHandle(peer.handle) }), 'good');
        close();
        await identityTrust.reopenLockedMessages(peer.userId);
      };
      // The code is long machine text: it is copied to send, not read. A
      // browser without the clipboard API, or one that refuses it (an
      // insecure origin, a denied permission), gets the code in a read-only
      // field instead, selected, to copy by hand.
      const handCopy = el('div', { class: 'safety-hand-copy', hidden: '' }, [
        el('label', { class: 'field-label', for: 'safety-my-code' }, [t('safety.myCode')]),
        el('textarea', {
          id: 'safety-my-code',
          class: 'safety-my-code',
          readonly: '',
          rows: '3',
          spellcheck: 'false',
          'aria-describedby': 'safety-my-code-hint',
          onfocus: (event) => event.target.select(),
        }, [safety.code]),
        el('div', { class: 'field-hint', id: 'safety-my-code-hint' }, [t('safety.copyByHand')]),
      ]);
      // The field is as tall as the code at its width, so no line is cut at
      // its bottom edge; it is sized again when the window's width changes.
      const showCodeToCopy = () => {
        handCopy.hidden = false;
        const field = handCopy.querySelector('textarea');
        if (!refitHandCopy) {
          refitHandCopy = () => {
            field.style.height = 'auto';
            const borders = field.offsetHeight - field.clientHeight;
            field.style.height = `${field.scrollHeight + borders}px`;
          };
          window.addEventListener('resize', refitHandCopy);
        }
        refitHandCopy();
        field.focus();
        field.select();
      };
      const copyCode = async () => {
        if (typeof navigator.clipboard?.writeText !== 'function') {
          showCodeToCopy();
          return;
        }
        try {
          await navigator.clipboard.writeText(safety.code);
          toast(t('safety.codeCopied'), 'good');
        } catch {
          showCodeToCopy();
        }
      };
      const compare = async () => {
        if (safety.matches(codeInput.value.trim())) await markVerified();
        else result.textContent = t('safety.mismatch', { handle: shownHandle(peer.handle) });
      };
      backdrop = el('div', { class: 'dialog-backdrop hidden', id: DIALOG_ID, role: 'presentation' }, [
        el('div', {
          class: 'dialog dialog-wide safety-dialog',
          role: 'dialog',
          'aria-modal': 'true',
          'aria-labelledby': 'safety-title',
        }, [
          el('div', { class: 'dialog-title', id: 'safety-title' }, [t('safety.title', { handle: shownHandle(peer.handle) })]),
          safety.pendingNoteKey
            ? el('div', { class: 'notice', role: 'alert' }, [
              icon('warning', 'notice-icon tone-warn'),
              el('div', { class: 'notice-text' }, [t(safety.pendingNoteKey, { handle: shownHandle(peer.handle) })]),
            ])
            : null,
          safety.remoteKey.verified ? el('div', { class: 'safety-status' }, [t('safety.alreadyVerified')]) : null,
          // Twelve groups of five, four to a line; the text keeps its spaces.
          el('div', { class: 'safety-number', id: 'safety-number' },
            safety.number.split(' ').flatMap((group, index) => [index > 0 ? ' ' : null, el('span', {}, [group])])),
          el('div', { class: 'dialog-sub' }, [t('safety.explain', { handle: shownHandle(peer.handle) })]),
          el('button', {
            type: 'button',
            class: 'btn btn-secondary safety-copy-code',
            'data-code': safety.code,
            onclick: copyCode,
          }, [icon('copy'), t('safety.copyCode')]),
          handCopy,
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
