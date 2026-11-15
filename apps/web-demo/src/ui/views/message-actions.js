// The menu a message opens on right-click (or a long press on touch):
// reactions, reply, copy, edit and delete for our own messages, forward,
// and block and report for a peer's message in a direct conversation. A
// deleted text can be put back in the composer for a few seconds.

import { shownHandle } from '../../domain/handles.js';
import { isTextKind } from '../../domain/ingest.js';
import { isPendingId } from '../../domain/local-messages.js';
import { senderToReport } from '../../features/report.js';
import { el } from '../dom.js';
import { actionToast, toast } from '../toast.js';

const QUICK_REACTIONS = ['👍', '❤️', '😂', '😢', '🔥', '🎉'];
const LONG_PRESS_MS = 500;
const UNDO_MS = 5_000;
const MENU_WIDTH_PX = 200;
const MENU_HEIGHT_PX = 240;

// send: src/app/services/send.js; safety: src/app/services/safety.js;
// composer, forwardDialog, reportDialog: the views the items lead to;
// confirm: src/ui/confirm.js.
export function createMessageActions({ store, send, safety, composer, forwardDialog, reportDialog, confirm }) {
  const { state } = store;
  let menu = null;
  // messageId -> { convId, text, expiresAt }, in memory only.
  const undoable = new Map();

  function close() {
    menu?.remove();
    menu = null;
  }

  function restore(messageId) {
    const entry = undoable.get(messageId);
    undoable.delete(messageId);
    if (!entry || Date.now() > entry.expiresAt) {
      toast('Too late to undo', 'error');
      return;
    }
    composer.restoreText(entry.convId, entry.text).then((inComposer) => {
      if (inComposer) toast('Put back in the message box. Press Enter to send it again', 'good');
    });
  }

  // The server's soft delete is what the peer sees and is not undone; the
  // undo puts the text back in the composer to be sent as a new message.
  async function remove(message) {
    const ok = await confirm({
      title: 'Delete message',
      body: 'This deletes the message for both of you. They will see that it was deleted.',
      okLabel: 'Delete',
      destructive: true,
    });
    if (!ok) return;
    const captured = await send.deleteMessage(message.id);
    if (!captured || captured.text === '') return;
    undoable.set(message.id, { ...captured, expiresAt: Date.now() + UNDO_MS });
    actionToast('Message deleted', 'Undo', () => restore(message.id), UNDO_MS);
    setTimeout(() => undoable.delete(message.id), UNDO_MS + 500);
  }

  function edit(message, convId) {
    if (!isTextKind(message.kind)) {
      toast("This message can't be edited", 'error');
      return;
    }
    const fresh = window.prompt('Edit message', message.displayText);
    if (fresh == null) return;
    const trimmed = fresh.trim();
    if (!trimmed || trimmed === message.displayText) return;
    send.edit(message, convId, trimmed);
  }

  async function copy(message) {
    try {
      await navigator.clipboard.writeText(message.displayText);
      toast('Copied', 'good');
    } catch {
      toast('Could not access the clipboard', 'error');
    }
  }

  // A menu item. The click does not reach the document (which closes
  // menus); the menu stays up while an in-place action (reply, copy, edit)
  // runs, and goes before one that opens a dialog.
  const item = (label, action, { className = 'msg-action-item', opensDialog = false } = {}) =>
    el('button', {
      class: className,
      onclick: async (event) => {
        event.stopPropagation();
        if (opensDialog) close();
        await action();
        if (!opensDialog) close();
      },
    }, [label]);
  const divider = () => el('div', { class: 'msg-action-divider' });

  function open(x, y, message, convId) {
    close();
    // No actions on a tombstone.
    if (message.deletedAt) return;
    const isMine = message.senderDeviceId === state.me?.deviceId;
    const peer = senderToReport(store.conversation(convId), message, state.me);
    const node = el('div', { class: 'msg-action-menu' }, [
      el('div', { class: 'msg-action-row' }, QUICK_REACTIONS.map((emoji) => el('button', {
        title: 'React',
        onclick: (event) => {
          event.stopPropagation();
          send.react(message.id, emoji);
          close();
        },
      }, [emoji]))),
      divider(),
      item('Reply', () => composer.startReply(convId, message)),
      isTextKind(message.kind) ? item('Copy', () => copy(message)) : null,
      ...(isMine && !isPendingId(message.id)
        ? [
          item('Edit', () => edit(message, convId)),
          item('Delete', () => remove(message), { className: 'msg-action-item danger', opensDialog: true }),
        ]
        : []),
      item('Forward', () => forwardDialog.open(message), { opensDialog: true }),
      // Only a message whose sender is known gets these: never our own, and
      // none in a group, where a sender's device names no member here.
      ...(peer
        ? [
          divider(),
          item('Block', () => block(peer), { className: 'msg-action-item danger', opensDialog: true }),
          item('Report', () => reportDialog.open(convId, message.id, peer), { opensDialog: true }),
        ]
        : []),
    ]);
    node.style.left = Math.min(x, window.innerWidth - MENU_WIDTH_PX) + 'px';
    node.style.top = Math.min(y, window.innerHeight - MENU_HEIGHT_PX) + 'px';
    document.body.appendChild(node);
    menu = node;
  }

  async function block(peer) {
    const ok = await confirm({
      title: 'Block @' + shownHandle(peer.handle),
      body: "You will no longer receive their messages, and they can't start a new chat with you. You can unblock them in Settings at any time.",
      okLabel: 'Block',
      destructive: true,
    });
    if (ok) await safety.block(peer.userId, shownHandle(peer.handle));
  }

  // The message a row in a conversation panel shows, with its conversation.
  function messageAt(target) {
    const row = target.closest('.msg-row');
    if (!row?.dataset?.msgId) return null;
    const convId = row.closest('.panel')?.dataset?.conv;
    if (!convId) return null;
    const message = store.messagesOf(convId).find((candidate) => candidate.id === row.dataset.msgId);
    return message ? { message, convId } : null;
  }

  return {
    mount() {
      document.addEventListener('click', close);
      document.addEventListener('scroll', close, true);
      document.addEventListener('contextmenu', (event) => {
        if (!event.target.closest('.msg-row')?.dataset?.msgId) return;
        event.preventDefault();
        const found = messageAt(event.target);
        if (found) open(event.clientX, event.clientY, found.message, found.convId);
      });
      let holdTimer = null;
      document.addEventListener('touchstart', (event) => {
        const found = messageAt(event.target);
        if (!found) return;
        const touch = event.touches[0];
        holdTimer = setTimeout(() => open(touch.clientX, touch.clientY, found.message, found.convId), LONG_PRESS_MS);
      }, { passive: true });
      document.addEventListener('touchend', () => clearTimeout(holdTimer), { passive: true });
      document.addEventListener('touchmove', () => clearTimeout(holdTimer), { passive: true });
    },
  };
}
