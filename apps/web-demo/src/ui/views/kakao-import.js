// Importing a KakaoTalk export (src/app/services/kakao-archives.js): one
// dialog reads, parses and previews the .txt in the browser and saves it as
// a read-only archive, listed under the conversations and opened in the
// panel area. The bytes never leave the device.

import { parseKakaoExport } from '../../../lib/kakao-import.js';
import { $, avatarFor, el } from '../dom.js';
import { dayKey, dayLabel, timeOfDay } from '../time.js';
import { toast } from '../toast.js';

const MAX_EXPORT_BYTES = 50 * 1024 * 1024;

const messageCount = (parsed) => parsed.messages.filter((message) => message.kind === 'msg').length;

function archivePanel(archive) {
  const list = el('div', { class: 'msgs', style: 'flex:1;overflow-y:auto;padding:14px' });
  let lastDay = null;
  for (const message of archive.messages) {
    if (message.kind === 'system') {
      list.appendChild(el('div', { class: 'day-divider' }, [el('span', {}, [message.body])]));
      continue;
    }
    if (!message.sender || !message.sentAt) continue;
    const sent = new Date(message.sentAt);
    const key = dayKey(sent);
    if (key !== lastDay) {
      list.appendChild(el('div', { class: 'day-divider' }, [el('span', {}, [dayLabel(sent)])]));
      lastDay = key;
    }
    // Who "me" was is not in the export: every message shows as received.
    list.appendChild(el('div', { class: 'group-stack' }, [
      el('div', { class: 'group-meta' }, [message.sender]),
      el('div', { class: 'msg-row them' }, [el('div', { class: 'msg first-of-group last-of-group' }, [el('span', { class: 'msg-text' }, [message.body])])]),
      el('div', { class: 'msg-time' }, [timeOfDay(sent)]),
    ]));
  }
  return el('div', { class: 'panel', dataset: { conv: archive.id } }, [
    el('div', { class: 'panel-header' }, [
      avatarFor(archive.title || 'kakao', 'md'),
      el('div', { class: 'panel-title' }, [
        el('div', { class: 'name' }, ['📥 ' + (archive.title || '카카오 아카이브')]),
        el('div', { class: 'sub' }, [`${archive.messageCount} 메시지 · 읽기 전용`]),
      ]),
    ]),
    el('div', { class: 'kakao-archive-banner' }, ['📥 ', el('strong', {}, ['카카오톡 아카이브']), ' — 답장 / 전송 불가. 이 브라우저에만 저장됨.']),
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
      toast('아카이브를 불러오지 못했어요', 'error');
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
        el('div', {
          dataset: { kakaoSection: '1' },
          style: 'padding:10px 14px 4px;font-size:11px;opacity:0.55;letter-spacing:0.05em;text-transform:uppercase',
        }, ['카카오 아카이브']),
        ...state.archives.map((meta) => el('button', {
          class: 'conv-item',
          style: 'background:transparent;border:0;color:inherit;cursor:pointer;width:100%;display:flex;align-items:center;gap:10px;padding:10px 14px;text-align:left',
          onclick: () => openArchive(meta),
        }, [
          avatarFor(meta.title || 'kakao', 'sm'),
          el('div', { style: 'flex:1' }, [
            el('div', { style: 'font-size:13px' }, [el('span', { class: 'kakao-conv-prefix' }, ['📥']), meta.title || '아카이브']),
            el('div', { style: 'font-size:11px;opacity:0.6' }, [`${meta.messageCount} 메시지 · 읽기 전용`]),
          ]),
        ])),
      ];
    },

    openDialog() {
      const fileInput = el('input', { type: 'file', id: 'kakao-file', accept: '.txt,text/plain' });
      const preview = el('div', { id: 'kakao-preview', class: 'hidden', style: 'margin-top:14px' });
      const error = el('div', { class: 'dialog-error', id: 'kakao-error', role: 'alert', 'aria-live': 'polite' });
      const cancelButton = el('button', { class: 'btn btn-ghost', id: 'kakao-cancel' }, ['취소']);
      const confirmButton = el('button', { class: 'btn btn-primary', id: 'kakao-confirm', disabled: 'disabled' }, ['아카이브로 저장']);
      const backdrop = el('div', { class: 'dialog-backdrop', role: 'presentation' }, [
        el('div', { class: 'dialog', role: 'dialog', 'aria-modal': 'true', 'aria-labelledby': 'kakao-title', style: 'width:480px;max-width:92vw' }, [
          el('div', { class: 'dialog-title', id: 'kakao-title' }, ['📥 카카오톡 채팅 가져오기']),
          el('div', { class: 'dialog-sub' }, [
            '카톡 → 채팅방 → 설정 → ',
            el('strong', {}, ['대화 내용 내보내기']),
            ' → 텍스트 파일 (.txt) 받은 거 여기에 떨어뜨리세요. ',
            el('strong', {}, ['읽기 전용 아카이브']),
            '로 저장되며, 이 브라우저 밖으로 절대 나가지 않아요.',
          ]),
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
          error.textContent = '.txt 파일만 지원합니다.';
          return;
        }
        if (file.size > MAX_EXPORT_BYTES) {
          error.textContent = '50MB 초과 — 아카이브 분할이 필요해요.';
          return;
        }
        try {
          parsed = parseKakaoExport(await file.text());
          title = file.name.replace(/\.txt$/i, '');
          const { participants, errors } = parsed;
          const more = participants.length > 4 ? ` 외 ${participants.length - 4}명` : '';
          preview.replaceChildren(el('div', { class: 'kakao-import-summary' }, [
            el('div', {}, [el('strong', {}, [String(messageCount(parsed))]), ' 개 메시지']),
            el('div', {}, [el('strong', {}, [String(participants.length)]), ` 명 참여 (${participants.slice(0, 4).join(', ')}${more})`]),
            errors.length > 0 ? el('div', { style: 'opacity:0.7;margin-top:4px' }, [`파싱 경고 ${errors.length}건 (계속 진행 가능)`]) : null,
          ]));
          preview.classList.remove('hidden');
          confirmButton.disabled = false;
        } catch (failure) {
          error.textContent = '파일을 읽지 못했어요: ' + (failure.message || 'unknown');
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
          toast('아카이브로 저장됨', 'good');
          close();
          await archives.load();
          store.notify('sidebar');
        } catch (failure) {
          error.textContent = '저장 실패: ' + (failure.message || 'unknown');
          confirmButton.disabled = false;
        }
      });
    },
  };
}
