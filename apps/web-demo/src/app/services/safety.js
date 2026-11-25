// Blocking, muting and reporting, on the API's safety routes:
//   GET    /safety/blocks                    blocked users
//   POST   /safety/blocks {userId}           block
//   DELETE /safety/blocks/:userId            unblock
//   POST   /safety/mutes/:cid {mutedForSeconds}  mute (null: unmute; absent: no end)
//   POST   /safety/reports                   an abuse report (src/features/report.js)

import { t } from '../../../i18n/i18n.js';
import { muteDurationLabel } from '../../domain/mute.js';
import { abuseReport } from '../../features/report.js';

// preferences: src/app/services/preferences.js; toast(message, kind).
export function createSafety({ store, stack, preferences, toast }) {
  const { authedApi } = stack;
  const { state } = store;
  // The session whose blocked list was asked for (one ask per session, so
  // a failing server is not asked again on every redraw).
  let askedFor = null;

  // Records what the server took and redraws the chats, whose composer and
  // menu follow it (src/ui/views/chat-view.js, chat-menu.js).
  function remember(userId, blocked) {
    if (!state.blocked) state.blocked = new Set();
    if (blocked) state.blocked.add(userId);
    else state.blocked.delete(userId);
    store.notify('panels');
  }

  // The blocked accounts, or null when the server could not be asked (so
  // a failure never reads as an empty list). An answer that comes after
  // the session changed is not kept.
  async function listBlocked() {
    const me = state.me;
    let users;
    try {
      const response = await authedApi('/safety/blocks');
      users = Array.isArray(response?.items) ? response.items : (Array.isArray(response) ? response : []);
    } catch {
      return null;
    }
    if (state.me === me) {
      state.blocked = new Set(users.map((user) => user.userId ?? user.id).filter(Boolean));
      store.notify('panels');
    }
    return users;
  }

  async function block(userId, handle, { quiet = false } = {}) {
    try {
      await authedApi('/safety/blocks', { method: 'POST', body: { userId } });
      remember(userId, true);
      if (!quiet) toast(t('safety.blocked', { handle }), 'good');
      return true;
    } catch {
      if (!quiet) toast(t('safety.blockFailed', { handle }), 'error');
      return false;
    }
  }

  return {
    // Whether the server took the block.
    block: (userId, handle) => block(userId, handle),

    // Whether the server took the unblock.
    async unblock(userId, handle) {
      try {
        await authedApi(`/safety/blocks/${userId}`, { method: 'DELETE' });
        remember(userId, false);
        toast(t('safety.unblocked', { handle }), 'good');
        return true;
      } catch {
        toast(t('safety.unblockFailed', { handle }), 'error');
        return false;
      }
    },

    listBlocked,

    // Asks the server once per session whom this account blocked, so that a
    // chat with them shows as blocked (src/ui/views/chat-view.js).
    loadBlocked() {
      if (!state.me || state.blocked || askedFor === state.me) return;
      askedFor = state.me;
      listBlocked();
    },

    // duration: seconds for a timed mute, 'always' for one with no end, or
    // null to unmute. The mute and its end are remembered here too, so it
    // holds before the server answers and ends on time.
    async setMute(conversationId, duration) {
      const body = duration === 'always' ? {} : { mutedForSeconds: duration };
      try {
        await authedApi(`/safety/mutes/${conversationId}`, { method: 'POST', body });
      } catch {
        toast(t('mute.failed'), 'error');
        return;
      }
      const { muted } = store.state;
      if (duration == null) {
        muted.delete(conversationId);
        toast(t('mute.undone'), 'good');
      } else if (duration === 'always') {
        muted.set(conversationId, null);
        toast(t('mute.doneAlways'), 'good');
      } else {
        muted.set(conversationId, Date.now() + duration * 1000);
        toast(t('mute.off', { duration: muteDurationLabel(duration) }), 'good');
      }
      preferences.setMutedConversations(muted);
      store.notify('panels', 'sidebar');
    },

    // Only the reason the user picked and the ids are sent: nothing typed,
    // and nothing of the message's content. messageId is left out for a
    // report about the whole chat. With alsoBlock the sender is blocked
    // once the report is in; handle is how the toasts name them.
    async report({ conversationId, messageId, sender, handle, reason, alsoBlock = false }) {
      try {
        await authedApi('/safety/reports', {
          method: 'POST',
          body: abuseReport({ reportedUserId: sender.userId, conversationId, messageId, reason }),
        });
      } catch {
        toast(t('report.failed'), 'error');
        return;
      }
      if (!alsoBlock) {
        toast(t('report.sent'), 'good');
        return;
      }
      if (await block(sender.userId, handle, { quiet: true })) toast(t('report.sentAndBlocked', { handle }), 'good');
      else toast(t('report.sentBlockFailed', { handle }), 'error');
    },
  };
}
