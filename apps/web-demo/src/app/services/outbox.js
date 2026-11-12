// The outbound queue: sealed envelopes (never plaintext) that could not go
// out when they were sent wait in IndexedDB and are delivered from here, by
// one tab at a time, with backoff, until the server takes them or refuses
// them for good.

import { ENVELOPE_VERSION_V2 } from '../../crypto/frame.js';
import { isPermanentRefusal, retryDelayMs } from '../../domain/delivery.js';
import { AuthError } from '../../platform/api-client.js';
import { outboundQueueEntry } from '../../platform/persist.js';

const LEAD_MS = 2000;

// BroadcastChannel-backed leader election. Several tabs of one identity
// would otherwise all drain the queue and repeat each POST (idempotency
// stops the duplicate write, not the wasted request). A tab leads only if no
// other has announced itself in the last ~2s.
function createLeaderElection() {
  const tabId = Math.random().toString(36).slice(2, 12) + '-' + Date.now().toString(36);
  let leaderUntil = 0;
  let channel = null;
  try {
    channel = new BroadcastChannel('veil-demo-outbound');
  } catch {}
  channel?.addEventListener('message', (event) => {
    if (event.data?.kind === 'lead' && event.data?.tab !== tabId) leaderUntil = Math.max(leaderUntil, Date.now() + LEAD_MS);
  });
  return function isLeader() {
    // No BroadcastChannel: an old browser, which drains as before.
    if (!channel) return true;
    const now = Date.now();
    if (leaderUntil > now) return false;
    try {
      channel.postMessage({ kind: 'lead', tab: tabId });
    } catch {}
    leaderUntil = now + LEAD_MS;
    return true;
  };
}

// toast(message, kind).
export function createOutbox({ store, stack, messages, toast }) {
  const { state } = store;
  const isLeader = createLeaderElection();
  const findOwn = (convId, clientMessageId) => store.messagesOf(convId).findIndex((m) => m.clientMessageId === clientMessageId);

  async function drain() {
    if (!state.me) return;
    if (!isLeader()) return;
    const items = await stack.idb.all('outbound');
    for (const item of items) {
      // Envelopes an earlier build queued in a retired format are dropped,
      // never sent.
      if (item.envelope?.version !== ENVELOPE_VERSION_V2) {
        await stack.identityDb.delete('outbound', item.clientMessageId);
        continue;
      }
      if (item.nextRetryAt && item.nextRetryAt > Date.now()) continue;
      try {
        const sent = await stack.authedApi('/messages', {
          method: 'POST',
          body: { conversationId: item.conversationId, clientMessageId: item.clientMessageId, envelope: item.envelope },
        });
        await stack.secure.acknowledge(sent.message);
        const list = store.messagesOf(item.conversationId);
        const index = findOwn(item.conversationId, item.clientMessageId);
        // The queue holds no plaintext: the optimistic view (if this tab
        // still has it) is reused, otherwise our content comes from the store.
        const view = await messages.ingest(sent.message, { previous: index >= 0 ? list[index] : null });
        if (index >= 0) list[index] = view;
        else list.push(view);
        state.messagesByConv.set(item.conversationId, list);
        const conv = store.conversation(item.conversationId);
        if (conv) conv.lastMessage = view;
        await stack.identityDb.delete('outbound', item.clientMessageId);
        await messages.persistMessage(view);
        if (store.isOnScreen(item.conversationId)) store.notify('panels');
        store.notify('sidebar');
      } catch (error) {
        // The session ended; keep the queue for after the next restore.
        if (error instanceof AuthError) return;
        const attempts = (item.attempts ?? 0) + 1;
        await stack.identityDb.put('outbound', { ...item, attempts, nextRetryAt: Date.now() + retryDelayMs(attempts) });
        if (isPermanentRefusal(error)) {
          await stack.identityDb.delete('outbound', item.clientMessageId);
          // The bubble keeps the sealed envelope, in memory only, for Retry.
          const index = findOwn(item.conversationId, item.clientMessageId);
          if (index >= 0) Object.assign(store.messagesOf(item.conversationId)[index], { _status: 'failed', _envelope: item.envelope });
          toast('전송 실패: ' + error.message, 'error');
          store.notify('panels');
        }
      }
    }
  }

  return {
    drain,

    // Puts a failed send back in the queue, its sealed envelope as it was,
    // to go out on the next drain: the queued entry, or the envelope a
    // refused send left with its bubble. A send that was never sealed (its
    // upload or seal failed) has nothing to send again and stays failed.
    async retry(convId, clientMessageId) {
      if (!clientMessageId) return;
      const index = findOwn(convId, clientMessageId);
      if (index < 0) return;
      const message = store.messagesOf(convId)[index];
      const queued = await stack.idb.get('outbound', clientMessageId);
      const envelope = queued?.envelope ?? message._envelope;
      if (!envelope) {
        toast('다시 보낼 내용이 없어요. 새로 보내주세요.', 'error');
        return;
      }
      await stack.identityDb.put('outbound', queued
        ? { ...queued, attempts: 0, nextRetryAt: 0 }
        : outboundQueueEntry({ clientMessageId, conversationId: convId, envelope }));
      delete message._envelope;
      message._status = 'pending';
      store.notify('panels');
      drain();
    },

    async cancel(convId, clientMessageId) {
      if (!clientMessageId) return;
      const list = store.messagesOf(convId);
      const index = findOwn(convId, clientMessageId);
      if (index >= 0) {
        list.splice(index, 1);
        state.messagesByConv.set(convId, list);
      }
      try {
        await stack.identityDb.delete('outbound', clientMessageId);
      } catch {}
      store.notify('panels');
      toast('전송 취소됨');
    },
  };
}
