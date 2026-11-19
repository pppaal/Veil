// The conversation panels: one, or two side by side in split view. Each is
// redrawn whole on every change; scroll position and composer focus are
// carried across redraws, and the peer messages it shows are marked read.

import { t } from '../../../i18n/i18n.js';
import { expiryNow } from '../../core/expiry.js';
import { isLegacyIdentity } from '../../crypto/identity.js';
import { shownHandle } from '../../domain/handles.js';
import { isGone, isShown } from '../../domain/ingest.js';
import { isPendingId } from '../../domain/local-messages.js';
import { reactionsByTarget } from '../../domain/reactions.js';
import { $, avatarFor, el, icon, iconButton } from '../dom.js';
import { shortcutLabel } from '../keys.js';
import { toast } from '../toast.js';
import { createChatMenu } from './chat-menu.js';
import { holdTextKey } from './key-change-banner.js';

// Near enough to the bottom to follow new messages down.
const NEAR_BOTTOM_PX = 120;

// messageList, composer, keyChangeBanner, safetyDialog, panelSearch: the
// views a panel is made of; reportDialog: what the menu's Report opens;
// messages: src/app/services/messages.js; safety:
// src/app/services/safety.js; confirm: src/ui/confirm.js; backToList: a
// phone's way from the chat to the list (src/ui/views/tabs.js).
export function createChatView({ store, stack, messages, messageList, composer, keyChangeBanner, safetyDialog, panelSearch, reportDialog, safety, confirm, backToList }) {
  const { state } = store;
  const readMarked = new Set(); // message ids this session marked read
  const observers = new Map(); // convId -> IntersectionObserver
  // convId -> whether the key its safety number is about was verified, as
  // last read: a redraw shows it at once, and the read that follows
  // corrects it.
  const verifiedKeys = new Map();

  async function markRead(messageId) {
    if (readMarked.has(messageId)) return;
    readMarked.add(messageId);
    try {
      await stack.authedApi(`/messages/${messageId}/read`, { method: 'POST', body: {} });
    } catch {
      readMarked.delete(messageId);
    }
  }

  // Marks a peer message read once half of it has been in view while the
  // tab is visible and its panel is shown.
  function observeReads(convId, list) {
    observers.get(convId)?.disconnect();
    const observer = new IntersectionObserver((entries) => {
      if (document.visibilityState !== 'visible' || !store.isOnScreen(convId)) return;
      for (const entry of entries) {
        if (entry.intersectionRatio < 0.5) continue;
        const messageId = entry.target.dataset.msgId;
        if (!messageId || isPendingId(messageId)) continue;
        const message = store.messagesOf(convId).find((candidate) => candidate.id === messageId);
        if (!message || message.senderDeviceId === state.me.deviceId || message.readAt) continue;
        markRead(messageId);
        observer.unobserve(entry.target);
      }
    }, { root: list, threshold: [0.5] });
    observers.set(convId, observer);
    for (const row of list.querySelectorAll('.msg-row.them')) observer.observe(row);
  }

  // Deletes this device's copy of a conversation's history: its content key
  // is destroyed (src/platform/content-store.js), which no copy of the
  // stored records survives, and the cached envelopes go with it.
  async function deleteLocalHistory(convId) {
    const ok = await confirm({ title: t('history.delete'), body: t('history.deleteBody'), okLabel: t('history.deleteConfirm'), destructive: true });
    if (!ok) return;
    const conv = store.conversation(convId);
    const known = [...store.messagesOf(convId), conv?.lastMessage].filter((message) => message?.id && !isPendingId(message.id));
    try {
      await stack.secure.forgetConversation(convId, Math.max(0, ...known.map((message) => message.conversationOrder ?? 0)));
      for (const message of known) await messages.uncache(message);
    } catch {
      toast(t('history.deleteFailed'), 'error');
      return;
    }
    messages.setMessages(convId, []);
    if (conv) conv.lastMessage = null;
    store.notify('sidebar', 'panels');
  }

  const chatMenu = createChatMenu({ store, safety, reportDialog, confirm, clearHistory: deleteLocalHistory });

  // Only typing shows under the name: nothing tells this device whether a
  // contact is online.
  function subtitle(conv, peer) {
    if (peer && state.typing.get(conv.id)?.has(peer.userId)) return { text: t('chat.typing'), className: 'sub typing' };
    return { text: '', className: 'sub' };
  }

  // Whether the user compared this conversation's safety number, so that a
  // contact they verified looks different from one under the same handle
  // they did not (src/features/secure-messaging.js safetyKey: false while
  // a change waits for review). A check in the success colour; the word is
  // there for assistive technology.
  function verifiedBadge(convId) {
    const badge = el('span', { class: 'verified-badge', title: t('safety.verifiedBadgeTitle') }, [
      icon('check'),
      el('span', { class: 'sr-only' }, [t('safety.verifiedBadge')]),
    ]);
    badge.hidden = !verifiedKeys.get(convId);
    stack.secure.safetyKey(convId).then((key) => {
      verifiedKeys.set(convId, Boolean(key?.verified));
      badge.hidden = !key?.verified;
    }).catch(() => {});
    return badge;
  }

  // On a phone the chat takes the whole screen and the list's bar is
  // hidden, so the chat's own bar leads with the way back (app.css shows
  // the button only there), as Signal, WhatsApp and Telegram do. Only the
  // main panel has it.
  function header(conv, peer, directPeer, legacyIdentity) {
    const sub = subtitle(conv, peer);
    const muted = store.isMuted(conv.id);
    const back = conv.id === state.activeConv
      ? iconButton('back', t('shell.back'), { class: 'icon-btn icon-btn-only-mobile panel-back', id: 'back-to-list', onclick: backToList })
      : null;
    return el('div', { class: 'panel-header' }, [
      back,
      avatarFor(peer?.handle ?? '?', 'sm'),
      el('div', { class: 'panel-title' }, [
        el('div', { class: 'panel-title-row' }, [
          el('div', { class: 'name' }, ['@' + shownHandle(peer?.handle)]),
          directPeer && !legacyIdentity ? verifiedBadge(conv.id) : null,
          muted ? el('span', { class: 'muted-mark', title: t('mute.doneAlways') }, [icon('bell-off'), el('span', { class: 'sr-only' }, [t('mute.doneAlways')])]) : null,
        ]),
        el('div', { class: sub.className }, [sub.text]),
      ]),
      el('div', { class: 'panel-actions' }, [
        iconButton('search', t('chat.findShortcut', { shortcut: shortcutLabel('F') }), { onclick: () => panelSearch.open(conv.id) }),
        directPeer && !legacyIdentity ? iconButton('shield', t('safety.open'), { onclick: () => safetyDialog.open(conv.id, directPeer) }) : null,
        iconButton('more', t('chat.menu'), {
          class: 'icon-btn chat-menu-btn',
          'aria-haspopup': 'menu',
          onclick: (event) => chatMenu.open(event.currentTarget, conv.id, directPeer),
        }),
      ]),
    ]);
  }

  // Where the composer was, while this account blocks the peer: one line
  // and the way back (WhatsApp's "You blocked this contact", mobile's
  // blocked chat). Unblock asks nothing: it is undone as easily.
  function blockedBar(peer) {
    const handle = shownHandle(peer.handle);
    return el('div', { class: 'panel-blocked' }, [
      el('span', { class: 'panel-blocked-line' }, [t('chat.blockedLine', { handle })]),
      el('button', { class: 'text-btn', type: 'button', onclick: () => safety.unblock(peer.userId, handle) }, [t('chat.unblock')]),
    ]);
  }

  function renderPanel(convId) {
    const conv = store.conversation(convId);
    if (!conv) return null;
    // The header, and the label of every message this device did not send,
    // name the peer the conversation's crypto is about
    // (src/domain/conversations.js shownPeer).
    const peer = stack.shownPeer(conv);
    const all = store.messagesOf(conv.id);
    // Reactions change what their targets show and are never bubbles of
    // their own; expired messages and history this device deleted are not
    // shown.
    const now = expiryNow();
    const reactions = reactionsByTarget(all.filter((message) => !isGone(message, now)));
    const shown = all.filter((message) => isShown(message, now));
    // Sessions, pins and safety numbers exist only in direct conversations:
    // the web demo cannot encrypt to a group, so it does not offer to send.
    // A key change waiting for review raises its banner but does not stop
    // sending: the cipher seals only to an identity the pins admit, and a
    // send it refuses says why (src/app/services/send.js). A conversation
    // held for the handle it is listed under (src/domain/peer-bindings.js
    // hold: one this device knows under another account, or one no honest
    // server issues) opens and sends nothing until the user chooses to talk
    // to that account.
    const directPeer = stack.peerOf(conv.id);
    // Whom this account blocked is asked once a session, the first time a
    // chat with someone is drawn; the answer redraws it.
    if (directPeer) safety.loadBlocked();
    const blocked = Boolean(directPeer && store.isBlocked(directPeer.userId));
    const keyChanged = Boolean(directPeer && stack.trust.pendingChange(directPeer.userId));
    const hold = directPeer ? stack.bindings.hold(conv.id, directPeer) : null;
    const legacyIdentity = isLegacyIdentity(state.me);
    let placeholder = t('msg.input.placeholder');
    if (!directPeer) placeholder = t('group.composerFrozen');
    if (hold) placeholder = t(holdTextKey(hold, 'composerFrozen'));
    if (legacyIdentity) placeholder = t('legacy.composerFrozen');

    // Scroll position from the previous drawing of this conversation.
    const previous = document.querySelector(`.panel-msgs[data-conv="${convId}"]`);
    let followBottom = true;
    let scrollTop = state.scrollTops.get(convId) ?? 0;
    if (previous) {
      scrollTop = previous.scrollTop;
      followBottom = previous.scrollHeight - previous.scrollTop - previous.clientHeight <= NEAR_BOTTOM_PX;
    }
    const list = messageList.render(convId, { shown, reactions, peerHandle: peer?.handle, group: !directPeer });
    list.addEventListener('scroll', () => state.scrollTops.set(convId, list.scrollTop));
    const { node: composerNode, textarea } = blocked
      ? { node: blockedBar(directPeer), textarea: null }
      : composer.render(convId, {
        frozen: legacyIdentity || !directPeer || Boolean(hold),
        placeholder,
        peerHandle: peer?.handle,
      });
    const panel = el('div', { class: 'panel', dataset: { conv: convId } }, [
      header(conv, peer, directPeer, legacyIdentity),
      hold ? keyChangeBanner.renderHold(convId, directPeer, hold) : null,
      keyChanged ? keyChangeBanner.render(convId, directPeer) : null,
      panelSearch.render(convId),
      list,
      composerNode,
    ]);

    requestAnimationFrame(() => {
      list.scrollTop = followBottom ? list.scrollHeight : scrollTop;
      if (state.focusClaims.has(convId) && state.activeConv === convId) {
        state.focusClaims.delete(convId);
        textarea?.focus();
      }
    });
    if (store.isOnScreen(convId)) requestAnimationFrame(() => observeReads(convId, list));
    return panel;
  }

  return {
    render() {
      const panels = $('panels');
      const slots = [state.activeConv, state.splitView ? state.secondaryConv : null].filter(Boolean);
      if (slots.length === 0) {
        panels.replaceChildren(el('div', { class: 'panel-empty' }, [
          el('div', { class: 'empty-title' }, [t('chat.empty.title')]),
        ]));
      } else {
        panels.replaceChildren(...slots.map(renderPanel).filter(Boolean));
      }
      requestAnimationFrame(() => panelSearch.highlight());
    },

    forgetReads: () => readMarked.clear(),
  };
}
