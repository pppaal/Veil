// The conversation panels: one, or two side by side in split view. Each is
// redrawn whole on every change; scroll position and composer focus are
// carried across redraws, and the peer messages it shows are marked read.

import { t } from '../../../i18n/i18n.js';
import { expiryNow } from '../../core/expiry.js';
import { isLegacyIdentity } from '../../crypto/identity.js';
import { shownHandle } from '../../domain/handles.js';
import { isGone, isShown } from '../../domain/ingest.js';
import { isPendingId } from '../../domain/local-messages.js';
import { muteSecondsFromMinutes } from '../../domain/mute.js';
import { reactionsByTarget } from '../../domain/reactions.js';
import { $, avatarFor, el, emptyStateSvg, isNarrowLayout } from '../dom.js';
import { toast } from '../toast.js';
import { holdTextKey } from './key-change-banner.js';

// Near enough to the bottom to follow new messages down.
const NEAR_BOTTOM_PX = 120;

// messageList, composer, keyChangeBanner, safetyDialog, panelSearch: the
// views a panel is made of; messages: src/app/services/messages.js;
// safety: src/app/services/safety.js; confirm: src/ui/confirm.js.
export function createChatView({ store, stack, messages, messageList, composer, keyChangeBanner, safetyDialog, panelSearch, safety, confirm }) {
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
    } catch (error) {
      toast(t('history.deleteFailed', { error: error.message }), 'error');
      return;
    }
    messages.setMessages(convId, []);
    if (conv) conv.lastMessage = null;
    store.notify('sidebar', 'panels');
  }

  // Unmuted, a click asks how long to mute for; muted, it unmutes.
  async function toggleMute(convId, button) {
    if (state.muted.has(convId)) {
      await safety.setMute(convId, null);
      button.textContent = '🔔';
      return;
    }
    const minutes = window.prompt('알림 끄기 기간을 분 단위로 입력하세요 (예: 60 = 1시간, 1440 = 24시간, 999999 = 영구):', '60');
    if (!minutes) return;
    await safety.setMute(convId, muteSecondsFromMinutes(minutes));
    button.textContent = '🔕';
  }

  const headerButton = (label, glyph, onclick, title = label) =>
    el('button', { class: 'icon-btn', 'aria-label': label, title, onclick, style: 'padding: 4px 8px; opacity: 0.7;' }, [glyph]);

  // Typing beats presence beats the conversation id.
  function subtitle(conv, peer) {
    if (peer && state.typing.get(conv.id)?.has(peer.userId)) return { text: '입력 중…', className: 'sub typing' };
    if (peer && state.online.has(peer.userId)) return { text: '온라인', className: 'sub online' };
    return { text: `대화 ${conv.id.slice(0, 8)}`, className: 'sub' };
  }

  // Whether the user compared this conversation's safety number, so that a
  // contact they verified looks different from one under the same handle
  // they did not (src/features/secure-messaging.js safetyKey: false while
  // a change waits for review).
  function verifiedBadge(convId) {
    const badge = el('span', { class: 'verified-badge', title: t('safety.verifiedBadgeTitle') }, [t('safety.verifiedBadge')]);
    badge.hidden = !verifiedKeys.get(convId);
    stack.secure.safetyKey(convId).then((key) => {
      verifiedKeys.set(convId, Boolean(key?.verified));
      badge.hidden = !key?.verified;
    }).catch(() => {});
    return badge;
  }

  function header(conv, peer, directPeer, legacyIdentity) {
    const avatar = avatarFor(peer?.handle ?? '?', 'md');
    avatar.appendChild(el('span', { class: 'presence-dot' }));
    if (peer && state.online.has(peer.userId)) avatar.classList.add('online');
    const sub = subtitle(conv, peer);
    return el('div', { class: 'panel-header' }, [
      avatar,
      el('div', { class: 'panel-title' }, [el('div', { class: 'name' }, ['@' + shownHandle(peer?.handle)]), el('div', { class: sub.className }, [sub.text])]),
      directPeer && !legacyIdentity ? verifiedBadge(conv.id) : null,
      headerButton('대화에서 찾기 (Ctrl/Cmd+F)', '🔍', () => panelSearch.open(conv.id), '대화에서 찾기'),
      directPeer && !legacyIdentity ? headerButton(t('safety.open'), '🛡', () => safetyDialog.open(conv.id, directPeer)) : null,
      headerButton(t('history.delete'), '🗑', () => deleteLocalHistory(conv.id)),
      el('button', {
        class: 'mute-toggle',
        'aria-label': '알림 토글',
        title: '알림 토글',
        onclick: (event) => toggleMute(conv.id, event.currentTarget),
      }, [state.muted.has(conv.id) ? '🔕' : '🔔']),
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
    const keyChanged = Boolean(directPeer && stack.trust.pendingChange(directPeer.userId));
    const hold = directPeer ? stack.bindings.hold(conv.id, directPeer) : null;
    const legacyIdentity = isLegacyIdentity(state.me);
    // A phone has no room for the key hint, and no Enter key to explain.
    let placeholder = isNarrowLayout() ? '메시지 입력' : '메시지 입력 (Enter 전송, Shift+Enter 줄바꿈)';
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
    const list = messageList.render(convId, { shown, reactions, peerHandle: peer?.handle });
    list.addEventListener('scroll', () => state.scrollTops.set(convId, list.scrollTop));
    const { node: composerNode, textarea } = composer.render(convId, {
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
        textarea.focus();
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
        panels.replaceChildren(el('div', { class: 'panel-empty', style: 'display:flex' }, [
          emptyStateSvg('chat'),
          el('div', { class: 'empty-title' }, ['대화를 골라주세요']),
          el('div', { class: 'empty-sub' }, ['좌측에서 대화를 선택하거나 새로 시작하세요']),
        ]));
      } else {
        panels.replaceChildren(...slots.map(renderPanel).filter(Boolean));
      }
      requestAnimationFrame(() => panelSearch.highlight());
    },

    forgetReads: () => readMarked.clear(),
  };
}
