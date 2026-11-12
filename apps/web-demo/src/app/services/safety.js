// Blocking, muting and reporting, on the API's safety routes:
//   GET    /safety/blocks                    blocked users
//   POST   /safety/blocks {userId}           block
//   DELETE /safety/blocks/:userId            unblock
//   POST   /safety/mutes/:cid {mutedForSeconds}  mute (null: unmute)
//   POST   /safety/reports                   an abuse report (src/features/report.js)

import { t } from '../../../i18n/i18n.js';
import { muteDurationLabel } from '../../domain/mute.js';
import { abuseReport } from '../../features/report.js';

// preferences: src/app/services/preferences.js; toast(message, kind).
export function createSafety({ store, stack, preferences, toast }) {
  const { authedApi } = stack;

  return {
    async block(userId, handle) {
      try {
        await authedApi('/safety/blocks', { method: 'POST', body: { userId } });
        toast(`@${handle} 차단됨`, 'good');
      } catch (error) {
        toast('차단 실패: ' + (error.message || 'unknown'), 'error');
      }
    },

    async unblock(userId, handle) {
      try {
        await authedApi(`/safety/blocks/${userId}`, { method: 'DELETE' });
        toast(`@${handle} 차단 해제됨`, 'good');
      } catch (error) {
        toast('해제 실패: ' + (error.message || 'unknown'), 'error');
      }
    },

    async listBlocked() {
      try {
        const response = await authedApi('/safety/blocks');
        return Array.isArray(response?.items) ? response.items : (Array.isArray(response) ? response : []);
      } catch {
        return [];
      }
    },

    // seconds: how long notifications stay off; null or 0 turns them on.
    // The mute is remembered here too, so it holds before the server answers.
    async setMute(conversationId, seconds) {
      try {
        await authedApi(`/safety/mutes/${conversationId}`, { method: 'POST', body: { mutedForSeconds: seconds } });
        if (seconds == null || seconds <= 0) {
          store.state.muted.delete(conversationId);
          toast('알림 켜짐', 'good');
        } else {
          store.state.muted.add(conversationId);
          toast(`${muteDurationLabel(seconds)} 동안 알림 끔`, 'good');
        }
        preferences.setMutedConversations(store.state.muted);
        store.notify('panels', 'sidebar');
      } catch (error) {
        toast('알림 설정 실패: ' + (error.message || 'unknown'), 'error');
      }
    },

    // Only the reason the user picked and the ids are sent: nothing typed,
    // and nothing of the message's content.
    async report({ conversationId, messageId, sender, reason }) {
      try {
        await authedApi('/safety/reports', {
          method: 'POST',
          body: abuseReport({ reportedUserId: sender.userId, conversationId, messageId, reason }),
        });
        toast(t('report.sent'), 'good');
      } catch (error) {
        toast(t('report.failed', { error: error.message || 'unknown' }), 'error');
      }
    },
  };
}
