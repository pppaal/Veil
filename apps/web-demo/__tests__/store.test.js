import { describe, expect, it } from 'vitest';

import { createStore } from '../src/app/store.js';
import { reactionTally } from '../src/domain/reactions.js';

describe('the app store', () => {
  it('starts from the preferences it is given', () => {
    const store = createStore({ mutedConversations: new Set(['c1']), soundsEnabled: true });
    expect(store.state.muted.has('c1')).toBe(true);
    expect(store.state.soundsEnabled).toBe(true);
    expect(createStore().state.muted.size).toBe(0);
  });

  it('notifies the subscribers of each topic, synchronously and in order', () => {
    const store = createStore();
    const calls = [];
    store.subscribe('sidebar', () => calls.push('sidebar'));
    store.subscribe('panels', () => calls.push('panels:1'));
    store.subscribe('panels', () => calls.push('panels:2'));
    store.notify('panels', 'sidebar', 'tabs');
    expect(calls).toEqual(['panels:1', 'panels:2', 'sidebar']);
  });

  it('finds messages loaded or as a conversation last message', () => {
    const store = createStore();
    const last = { id: 'm9' };
    store.state.conversations = [{ id: 'c1', lastMessage: last }];
    store.state.messagesByConv.set('c1', [{ id: 'm1' }, { id: 'm2' }]);
    expect(store.findMessage('c1', 'm2')).toEqual({ id: 'm2' });
    expect(store.findMessage('c1', 'm9')).toBe(last);
    expect(store.findMessage('c1', 'mX')).toBeNull();
    expect(store.locateMessage('m2')).toMatchObject({ convId: 'c1', index: 1, message: { id: 'm2' } });
    expect(store.locateMessage('m9')).toBeNull();
    expect(store.messagesOf('c2')).toEqual([]);
  });

  it('puts an own message in place of its pending copy, or last', () => {
    const store = createStore();
    store.putOwnMessage('c1', 'k1', { id: 'p1', clientMessageId: 'k1' });
    store.putOwnMessage('c1', 'k2', { id: 'p2', clientMessageId: 'k2' });
    store.putOwnMessage('c1', 'k1', { id: 'm1', clientMessageId: 'k1' });
    expect(store.messagesOf('c1').map((message) => message.id)).toEqual(['m1', 'p2']);
  });

  it('tells what the panels show', () => {
    const store = createStore();
    Object.assign(store.state, { activeConv: 'c1', secondaryConv: 'c2' });
    expect(['c1', 'c2', 'c3'].map(store.isOnScreen)).toEqual([true, true, false]);
  });

  it('drops the session state on reset and keeps the preferences', () => {
    const store = createStore({ mutedConversations: new Set(['c1']), soundsEnabled: true });
    Object.assign(store.state, { me: { handle: 'a' }, conversations: [{ id: 'c1' }], conversationsLoaded: true, activeConv: 'c1', openTabs: ['c1'], splitView: true });
    store.state.messagesByConv.set('c1', []);
    store.state.drafts.set('c1', 'unsent');
    store.state.replyDrafts.set('c1', { id: 'm1' });
    store.state.typing.set('c1', new Map());
    store.state.online.add('u1');
    store.state.archives = [{ id: 'kakao-1' }];
    store.resetSession();
    expect(store.state).toMatchObject({ me: null, conversations: [], conversationsLoaded: false, activeConv: null, openTabs: [], splitView: false });
    for (const field of ['messagesByConv', 'drafts', 'replyDrafts', 'typing', 'online']) expect(store.state[field].size).toBe(0);
    expect(store.state.muted.has('c1')).toBe(true);
    expect(store.state.soundsEnabled).toBe(true);
    expect(store.state.archives).toEqual([{ id: 'kakao-1' }]);
  });
});

describe('reactionTally', () => {
  it('counts each emoji in first-seen order and marks ours', () => {
    const tally = reactionTally([
      { senderDeviceId: 'd-bob', emoji: '👍' },
      { senderDeviceId: 'd-me', emoji: '🔥' },
      { senderDeviceId: 'd-carol', emoji: '👍' },
    ], 'd-me');
    expect([...tally]).toEqual([['👍', { count: 2, mine: false }], ['🔥', { count: 1, mine: true }]]);
    expect(reactionTally(undefined, 'd-me').size).toBe(0);
  });
});
