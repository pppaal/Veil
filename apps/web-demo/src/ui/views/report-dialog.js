// Reporting a peer's message (src/features/report.js): the user picks one of
// the API's reasons, and only that reason and the ids are sent.

import { t } from '../../../i18n/i18n.js';
import { REPORT_REASONS } from '../../features/report.js';
import { trapFocus } from '../confirm.js';
import { $, el } from '../dom.js';

const DIALOG_ID = 'report-dialog';

// safety: src/app/services/safety.js; dialogs: src/ui/dialogs.js.
export function createReportDialog({ safety, dialogs }) {
  return {
    open(convId, messageId, sender) {
      if ($(DIALOG_ID)) return;
      let backdrop = null;
      const close = () => {
        dialogs.close(DIALOG_ID);
        backdrop.remove();
      };
      const submit = el('button', { class: 'btn btn-primary', id: 'report-submit', disabled: 'disabled' }, [t('report.submit')]);
      const choices = REPORT_REASONS.map((reason, index) => el('label', { style: 'display:block;padding:6px 0;cursor:pointer' }, [
        el('input', {
          type: 'radio',
          name: 'report-reason',
          value: reason,
          id: index === 0 ? 'report-first-reason' : null,
          onchange: () => {
            submit.disabled = false;
          },
        }),
        ' ' + t(`report.reason.${reason}`),
      ]));
      submit.addEventListener('click', async () => {
        const reason = backdrop.querySelector('input[name="report-reason"]:checked')?.value;
        if (!reason) return;
        close();
        await safety.report({ conversationId: convId, messageId, sender, reason });
      });
      backdrop = el('div', { class: 'dialog-backdrop hidden', id: DIALOG_ID, role: 'presentation' }, [
        el('div', { class: 'dialog', role: 'dialog', 'aria-modal': 'true', 'aria-labelledby': 'report-title', style: 'width:380px;max-width:92vw' }, [
          el('div', { class: 'dialog-title', id: 'report-title' }, [t('report.title', { handle: sender.handle })]),
          el('div', { class: 'dialog-sub' }, [t('report.explain')]),
          el('div', { role: 'radiogroup', 'aria-labelledby': 'report-title' }, choices),
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
