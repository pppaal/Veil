// Importing a KakaoTalk export (src/app/services/kakao-archives.js): one
// dialog reads, parses and previews the .txt in the browser and saves it as
// a read-only archive, listed under the conversations and opened in the
// panel area. The bytes never leave the device.

import { t } from '../../../i18n/i18n.js';
import { parseKakaoExport } from '../../../lib/kakao-import.js';
import { $, avatarFor, el } from '../dom.js';
import { dayKey, dayLabel, timeOfDay } from '../time.js';
import { toast } from '../toast.js';

const MAX_EXPORT_BYTES = 50 * 1024 * 1024;

const messageCount = (parsed) => parsed.messages.filter((message) => message.kind === 'msg').length;
const messagesLabel = (count) => (count === 1 ? t('kakao.oneMessage') : t('kakao.messages', { count }));

function archivePanel(archive) {
  const list = el('div', { class: 'archive-msgs' });
  let lastDay = null;
  for (const message of archive.messages) {
    if (message.kind === 'system') {
      list.appendChild(el('div', { class: 'day-divider' }, [message.body]));
      continue;
    }
    if (!message.sender || !message.sentAt) continue;
    const sent = new Date(message.sentAt);
    const key = dayKey(sent);
    if (key !== lastDay) {
      list.appendChild(el('div', { class: 'day-divider' }, [dayLabel(sent)]));
      lastDay = key;
    }
    // Who "me" was is not in the export: every message shows as received.
    list.appendChild(el('div', { class: 'msg-group them' }, [
      el('div', { class: 'group-stack' }, [
        el('div', { class: 'group-meta' }, [message.sender]),
        el('div', { class: 'msg-row them' }, [
          el('div', { class: 'msg first-of-group last-of-group' }, [
            el('span', { class: 'msg-text' }, [message.body]),
            el('span', { class: 'msg-meta' }, [timeOfDay(sent)]),
          ]),
        ]),
      ]),
    ]));
  }
  return el('div', { class: 'panel', dataset: { conv: archive.id } }, [
    el('div', { class: 'panel-header' }, [
      avatarFor(archive.title || 'kakao', 'sm'),
      el('div', { class: 'panel-title' }, [
        el('div', { class: 'name' }, [archive.title || t('kakao.archive')]),
        el('div', { class: 'sub' }, [messagesLabel(archive.messageCount)]),
      ]),
    ]),
    el('div', { class: 'kakao-archive-banner' }, [t('kakao.banner')]),
    list,
  ]);
}

// archives: src/app/services/kakao-archives.js.
export function createKakaoImport({ store, archives }) {
  const { state } = store;

  // Replaces the panels with the archive, read-only.
  async function openArchive(meta) {
    const panels = $('panels');
    if (!panels) return;
    const archive = await archives.open(meta.id);
    if (!archive) {
      toast(t('kakao.openFailed'), 'error');
      return;
    }
    panels.replaceChildren(archivePanel(archive));
    state.activeConv = archive.id;
  }

  return {
    // The sidebar rows for the imported archives, after the conversations.
    rows() {
      if (state.archives.length === 0) return [];
      return [
        el('div', { class: 'conv-section', dataset: { kakaoSection: '1' } }, [t('kakao.archives')]),
        ...state.archives.map((meta) => el('button', {
          class: 'conv-item',
          onclick: () => openArchive(meta),
        }, [
          avatarFor(meta.title || 'kakao', 'md'),
          el('div', { class: 'conv-meta' }, [
            el('div', { class: 'conv-row1' }, [el('span', { class: 'conv-name' }, [meta.title || t('kakao.untitled')])]),
            el('div', { class: 'conv-preview' }, [messagesLabel(meta.messageCount)]),
          ]),
        ])),
      ];
    },

    openDialog() {
      const fileInput = el('input', { type: 'file', id: 'kakao-file', class: 'kakao-file', accept: '.txt,text/plain' });
      const preview = el('div', { id: 'kakao-preview', class: 'kakao-import-summary hidden' });
      const error = el('div', { class: 'dialog-error', id: 'kakao-error', role: 'alert', 'aria-live': 'polite' });
      const cancelButton = el('button', { class: 'btn btn-ghost', id: 'kakao-cancel' }, [t('common.cancel')]);
      const confirmButton = el('button', { class: 'btn btn-primary', id: 'kakao-confirm', disabled: 'disabled' }, [t('kakao.save')]);
      const backdrop = el('div', { class: 'dialog-backdrop', role: 'presentation' }, [
        el('div', { class: 'dialog dialog-wide', role: 'dialog', 'aria-modal': 'true', 'aria-labelledby': 'kakao-title' }, [
          el('div', { class: 'dialog-title', id: 'kakao-title' }, [t('kakao.title')]),
          el('div', { class: 'dialog-sub' }, [t('kakao.howTo'), el('strong', {}, [t('kakao.exportChat')]), t('kakao.howToEnd')]),
          fileInput,
          preview,
          error,
          el('div', { class: 'dialog-actions' }, [cancelButton, confirmButton]),
        ]),
      ]);
      document.body.appendChild(backdrop);

      let parsed = null;
      let title = '';
      fileInput.addEventListener('change', async () => {
        error.textContent = '';
        const file = fileInput.files?.[0];
        if (!file) return;
        if (!file.name.endsWith('.txt')) {
          error.textContent = t('kakao.wrongType');
          return;
        }
        if (file.size > MAX_EXPORT_BYTES) {
          error.textContent = t('kakao.tooBig');
          return;
        }
        try {
          parsed = parseKakaoExport(await file.text());
          title = file.name.replace(/\.txt$/i, '');
          const { participants, errors } = parsed;
          const shown = participants.slice(0, 4).join(', ');
          const names = participants.length > 4 ? t('kakao.more', { names: shown, count: participants.length - 4 }) : shown;
          preview.replaceChildren(...[
            el('div', {}, [messagesLabel(messageCount(parsed))]),
            el('div', {}, [t('kakao.participants', { count: participants.length, names })]),
            errors.length > 0 ? el('div', {}, [t('kakao.unreadLines', { count: errors.length })]) : null,
          ].filter(Boolean));
          preview.classList.remove('hidden');
          confirmButton.disabled = false;
        } catch {
          error.textContent = t('kakao.readFailed');
        }
      });

      const close = () => backdrop.remove();
      cancelButton.addEventListener('click', close);
      backdrop.addEventListener('click', (event) => {
        if (event.target === backdrop) close();
      });
      confirmButton.addEventListener('click', async () => {
        if (!parsed) return;
        confirmButton.disabled = true;
        try {
          await archives.save(title, parsed);
          toast(t('kakao.saved'), 'good');
          close();
          await archives.load();
          store.notify('sidebar');
        } catch {
          error.textContent = t('kakao.saveFailed');
          confirmButton.disabled = false;
        }
      });
    },
  };
}
