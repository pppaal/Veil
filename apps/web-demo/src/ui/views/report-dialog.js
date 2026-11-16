// Reporting a peer, from one of their messages or from the chat's menu
// (src/features/report.js): the user picks one of the API's reasons, and
// only that reason and the ids are sent. One dialog, as the desktop apps
// have it: the reasons, what the report carries, and whether to block them
// too (on by default).

import { t } from '../../../i18n/i18n.js';
import { shownHandle } from '../../domain/handles.js';
import { REPORT_REASONS } from '../../features/report.js';
import { trapFocus } from '../confirm.js';
import { $, el } from '../dom.js';

const DIALOG_ID = 'report-dialog';

// The reasons in the order the mobile app lists them.
const SHOWN_ORDER = ['spam', 'scam', 'harassment', 'impersonation', 'violence', 'csam', 'other'].filter((reason) => REPORT_REASONS.includes(reason));

// safety: src/app/services/safety.js; dialogs: src/ui/dialogs.js.
export function createReportDialog({ safety, dialogs }) {
  return {
    // messageId: the message reported, or null for the whole chat.
    open(convId, messageId, sender) {
      if ($(DIALOG_ID)) return;
      const handle = shownHandle(sender.handle);
      let backdrop = null;
      const close = () => {
        dialogs.close(DIALOG_ID);
        backdrop.remove();
      };
      const submit = el('button', { class: 'btn btn-primary', id: 'report-submit', disabled: 'disabled' }, [t('report.submit')]);
      const choices = SHOWN_ORDER.map((reason, index) => el('label', { class: 'choice' }, [
        el('input', {
          type: 'radio',
          name: 'report-reason',
          value: reason,
          id: index === 0 ? 'report-first-reason' : null,
          onchange: () => {
            submit.disabled = false;
          },
        }),
        el('span', {}, [t(`report.reason.${reason}`)]),
      ]));
      const alsoBlock = el('input', { type: 'checkbox', id: 'report-also-block' });
      alsoBlock.checked = true;
      submit.addEventListener('click', async () => {
        const reason = backdrop.querySelector('input[name="report-reason"]:checked')?.value;
        if (!reason) return;
        const block = alsoBlock.checked;
        close();
        await safety.report({ conversationId: convId, messageId: messageId ?? undefined, sender, handle, reason, alsoBlock: block });
      });
      backdrop = el('div', { class: 'dialog-backdrop hidden', id: DIALOG_ID, role: 'presentation' }, [
        el('div', { class: 'dialog', role: 'dialog', 'aria-modal': 'true', 'aria-labelledby': 'report-title' }, [
          el('div', { class: 'dialog-title', id: 'report-title' }, [t('report.title', { handle })]),
          el('div', { class: 'choice-list', role: 'radiogroup', 'aria-labelledby': 'report-title' }, choices),
          el('div', { class: 'dialog-sub' }, [t(messageId ? 'report.explain' : 'report.explainChat')]),
          el('label', { class: 'check-row' }, [alsoBlock, el('span', {}, [t('report.alsoBlock', { handle })])]),
          el('div', { class: 'dialog-actions' }, [el('button', { class: 'btn btn-ghost', onclick: close }, [t('common.cancel')]), submit]),
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
      document.body.appendChild(backdrop);
      dialogs.open(DIALOG_ID, 'report-first-reason');
    },
  };
}
