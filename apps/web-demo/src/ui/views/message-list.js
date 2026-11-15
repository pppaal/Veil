// A conversation's messages as the panel shows them: day dividers, runs of
// bubbles per sender (src/domain/message-groups.js), replies, reactions,
// delivery state, and media bodies decrypted on first sight.

import { t } from '../../../i18n/i18n.js';
import { formatBytes } from '../../../lib/format.js';
import { snippetOf } from '../../domain/conversations.js';
import { shownHandle } from '../../domain/handles.js';
import { DELIVERY_LABELS, deliveryStatus, groupMessages, sentAt } from '../../domain/message-groups.js';
import { isPendingId } from '../../domain/local-messages.js';
import { KIND_LABELS } from '../../domain/payload.js';
import { reactionTally } from '../../domain/reactions.js';
import { fileExtension } from '../../domain/sanitize.js';
import { avatarFor, avatarIndex, el, icon } from '../dom.js';
import { dayKey, dayLabel, timeOfDay } from '../time.js';
import { toast } from '../toast.js';
import { toFragment } from '../markdown-dom.js';
import { openImageZoom } from './image-preview.js';

// The delivery state of an own message as the sprite draws it
// (src/domain/message-groups.js deliveryStatus).
const STATUS_ICONS = Object.freeze({
  pending: 'clock',
  failed: 'warning',
  sent: 'check',
  delivered: 'check-double',
  read: 'check-double',
});

// send: src/app/services/send.js; outbox: src/app/services/outbox.js;
// startReply(convId, message): src/ui/views/composer.js.
export function createMessageList({ store, send, outbox, startReply }) {
  const { state } = store;
  // Media handles already being materialized.
  const loading = new WeakSet();

  function holdersOf(convId, media) {
    const holders = store.messagesOf(convId).filter((message) => message.media === media);
    const last = store.conversation(convId)?.lastMessage;
    if (last?.media === media && !holders.includes(last)) holders.push(last);
    return holders;
  }

  // Materializes a media handle once, then attaches the blob URL to every
  // message object still carrying that handle (a refresh may have replaced
  // the one that asked).
  function ensureMediaUrl(message, field) {
    const { media, conversationId } = message;
    if (loading.has(media)) return;
    loading.add(media);
    media.materialize()
      .then((blob) => {
        const url = URL.createObjectURL(blob);
        const holders = holdersOf(conversationId, media);
        for (const holder of holders) holder[field] = url;
        if (holders.length === 0) URL.revokeObjectURL(url);
      })
      .catch(() => {
        for (const holder of holdersOf(conversationId, media)) holder._mediaFailed = true;
      })
      .finally(() => {
        if (store.isOnScreen(conversationId)) store.notify('panels');
      });
  }

  // Downloads go out as application/octet-stream under the sanitized name,
  // so a hostile file is saved, never rendered in our origin.
  async function downloadFile(message) {
    const { media } = message;
    if (!media) return;
    try {
      toast(t('media.downloading', { name: media.name }));
      const url = URL.createObjectURL(await media.materialize());
      const anchor = el('a', { href: url, download: media.name });
      document.body.appendChild(anchor);
      anchor.click();
      anchor.remove();
      setTimeout(() => URL.revokeObjectURL(url), 60_000);
    } catch (error) {
      toast(t('media.downloadFailed', { error: error.message || 'unknown' }), 'error');
    }
  }

  function imageBody(message) {
    const url = message._imageUrl;
    if (url) {
      return el('img', {
        class: 'msg-inline-image',
        src: url,
        alt: 'image',
        onclick: (event) => {
          event.stopPropagation();
          openImageZoom(url);
        },
      });
    }
    if (message._mediaFailed) return t('media.imageFailed');
    if (message.media) ensureMediaUrl(message, '_imageUrl');
    return el('span', { class: 'image-uploading' }, [KIND_LABELS.image]);
  }

  function voiceBody(message) {
    if (message._voiceUrl) {
      return el('audio', { class: 'msg-audio', controls: 'controls', src: message._voiceUrl, preload: 'metadata' });
    }
    if (message.media) ensureMediaUrl(message, '_voiceUrl');
    return KIND_LABELS.voice;
  }

  // File names are sender-controlled: the sanitized name and the real
  // extension show separately.
  function fileChip(message) {
    const name = message.media?.name ?? message._localFile?.name ?? t('media.file');
    const sizeBytes = message.media?.sizeBytes ?? message._localFile?.sizeBytes ?? 0;
    const extension = message.media?.extension ?? fileExtension(name);
    const size = formatBytes(sizeBytes);
    return el('button', {
      class: 'msg-file-chip',
      type: 'button',
      onclick: (event) => {
        event.stopPropagation();
        downloadFile(message);
      },
    }, [
      el('div', { class: 'msg-file-chip-icon' }, [icon('file')]),
      el('div', { class: 'msg-file-chip-meta' }, [
        el('div', { class: 'msg-file-chip-name' }, [name]),
        el('div', { class: 'msg-file-chip-size' }, [
          extension ? el('span', { class: 'msg-file-chip-ext' }, ['.' + extension]) : null,
          size ? t('media.clickToDownload', { size }) : 'Click to download',
        ]),
      ]),
    ]);
  }

  // Text goes through the DOM markdown builder; everything else renders from
  // the view's kind and media handle, so no decrypted payload is ever shown
  // as text.
  function body(message) {
    switch (message.kind) {
      case 'text':
      case 'reply':
        return el('span', {}, [toFragment(message.displayText)]);
      case 'image':
        return imageBody(message);
      case 'voice':
        return voiceBody(message);
      case 'file':
        return fileChip(message);
      default:
        return message.displayText;
    }
  }

  // Chips per emoji with a count, ours highlighted; a click toggles ours
  // through the same end-to-end path as the action menu.
  function reactionsRow(message, reactions) {
    const tally = reactionTally(reactions, state.me?.deviceId);
    if (tally.size === 0) return null;
    return el('div', { class: 'msg-reactions' }, [...tally].map(([emoji, entry]) => el('span', {
      class: 'msg-reaction-chip' + (entry.mine ? ' mine' : ''),
      title: t(entry.mine ? 'reaction.mineTitle' : 'reaction.joinTitle'),
      onclick: (event) => {
        event.stopPropagation();
        send.react(message.id, emoji);
      },
    }, [el('span', {}, [emoji]), ' ', el('span', { class: 'msg-reaction-count' }, [String(entry.count)])])));
  }

  // The quoted message at the top of a reply, behind a rule.
  function replyHead(replyToId, shown) {
    const target = shown.find((message) => message.id === replyToId);
    return el('div', { class: 'msg-reply-head' }, [target ? snippetOf(target, 80) : t('msg.reply.earlier')]);
  }

  // Time, and for our own messages the delivery state, at the end of the
  // last bubble of a run: one tick for sent, two for delivered, two and the
  // word for read. Assistive technology hears the state as a word.
  function bubbleMeta(group) {
    const last = group.msgs.at(-1);
    const time = timeOfDay(sentAt(last, Date.now()));
    if (!group.isMe) return el('span', { class: 'msg-meta' }, [time]);
    const status = deliveryStatus(last);
    const label = DELIVERY_LABELS[status];
    return el('span', { class: 'msg-meta' }, [
      time,
      el('span', { class: 'msg-status ' + status, title: label }, [
        icon(STATUS_ICONS[status]),
        el('span', { class: status === 'read' ? 'msg-status-word' : 'sr-only' }, [label]),
      ]),
    ]);
  }

  // Under a run whose last send failed: what happened and what to do.
  function failedLine(convId, group) {
    const last = group.msgs.at(-1);
    if (!group.isMe || deliveryStatus(last) !== 'failed') return null;
    return el('div', { class: 'msg-fail' }, [
      el('span', {}, [t('send.failed')]),
      el('button', { class: 'msg-action', onclick: () => outbox.retry(convId, last.clientMessageId) }, [t('msg.sendAgain')]),
      el('button', { class: 'msg-action danger', onclick: () => outbox.cancel(convId, last.clientMessageId) }, [t('common.cancel')]),
    ]);
  }

  function messageRow(convId, message, { isMe, first, last, shown, reactions, meta }) {
    const classes = ['msg'];
    if (first) classes.push('first-of-group');
    if (last) classes.push('last-of-group');
    if (message._status === 'pending') classes.push('pending');
    if (message._status === 'failed') classes.push('failed');
    if (message.deletedAt) classes.push('msg-deleted-bubble');
    const replyButton = isPendingId(message.id) ? null : el('button', {
      class: 'msg-reply-btn',
      'aria-label': t('msg.action.reply'),
      title: t('msg.action.reply'),
      onclick: (event) => {
        event.stopPropagation();
        startReply(convId, message);
      },
    }, [icon('reply')]);
    const bubble = el('div', { class: classes.join(' ') }, [
      message.replyTo ? replyHead(message.replyTo, shown) : null,
      el('span', { class: 'msg-text' }, [body(message)]),
      message.editedAt ? el('span', { class: 'msg-edited' }, [t('msg.edited')]) : null,
      // Read from a retired format: the bubble itself says so.
      message.legacy ? el('span', { class: 'msg-legacy-badge', title: t('legacy.badge') }, [t('legacy.badge')]) : null,
      meta,
    ]);
    const row = el('div', { class: 'msg-row ' + (isMe ? 'me' : 'them') }, [
      isMe ? replyButton : null,
      el('div', { class: 'msg-bubble-stack' }, [bubble, reactionsRow(message, reactions.get(message.id))]),
      isMe ? null : replyButton,
    ]);
    row.dataset.msgId = message.id;
    return row;
  }

  // The list node for a conversation's shown messages; reactions:
  // src/domain/reactions.js reactionsByTarget over the messages not gone.
  // In a group, each run of another member's messages is headed by their
  // handle in their own tint and has their avatar beside it. A one-to-one
  // chat names its one other person in the header, so its runs carry
  // neither, as in the mobile app.
  function render(convId, { shown, reactions, peerHandle, group: isGroup = false }) {
    const list = el('div', { class: 'panel-msgs', dataset: { conv: convId } });
    for (const day of groupMessages(shown, { me: state.me, peerHandle, dayKey, dayLabel })) {
      list.appendChild(el('div', { class: 'day-divider' }, [day.dayLabel]));
      for (const group of day.groups) {
        const stack = el('div', { class: 'group-stack' });
        const named = isGroup && !group.isMe;
        if (named) {
          const tint = ` name-${avatarIndex(group.senderHandle)}`;
          stack.appendChild(el('div', { class: 'group-meta' + tint }, ['@' + shownHandle(group.senderHandle)]));
        }
        group.msgs.forEach((message, index) => {
          const last = index === group.msgs.length - 1;
          stack.appendChild(messageRow(convId, message, {
            isMe: group.isMe,
            first: index === 0,
            last,
            shown,
            reactions,
            meta: last ? bubbleMeta(group) : null,
          }));
        });
        const failed = failedLine(convId, group);
        if (failed) stack.appendChild(failed);
        list.appendChild(el('div', { class: 'msg-group ' + (group.isMe ? 'me' : 'them') }, [
          named ? avatarFor(group.senderHandle, 'sm') : null,
          stack,
        ]));
      }
    }
    if (shown.length === 0) {
      list.appendChild(el('div', { class: 'panel-empty' }, [
        el('div', { class: 'empty-title' }, [t('msg.empty.title')]),
        el('div', { class: 'empty-sub' }, [t('msg.empty.sub')]),
      ]));
    }
    return list;
  }

  return { render };
}
