import { describe, expect, it } from 'vitest';

import { createSafety } from '../src/app/services/safety.js';
import { createStore } from '../src/app/store.js';

// Whom this account blocked, as the chat sees it: a blocked chat swaps its
// composer for "You blocked @x." and Unblock, and its menu offers Unblock
// in place of Block (src/ui/views/chat-view.js, chat-menu.js). The safety
// service keeps that set in step with what the server took.

function setup({ listed = [], fail = new Set() } = {}) {
  const store = createStore();
  store.state.me = { userId: 'me', handle: 'alex' };
  const calls = [];
  const redraws = [];
  store.subscribe('panels', () => redraws.push('panels'));
  const authedApi = async (path, options = {}) => {
    const method = options.method ?? 'GET';
    calls.push(`${method} ${path}`);
    if (fail.has(method)) throw new Error('unreachable');
    if (method === 'GET' && path === '/safety/blocks') return { items: listed };
    return {};
  };
  const toasts = [];
  const safety = createSafety({
    store,
    stack: { authedApi },
    preferences: { setMutedConversations() {} },
    toast: (message, kind) => toasts.push([message, kind]),
  });
  return { store, safety, calls, redraws, toasts };
}

describe('the blocked state the chat shows', () => {
  it('follows a block and an unblock the server took, and redraws the chats', async () => {
    const { store, safety, redraws } = setup();
    expect(store.isBlocked('sam')).toBe(false);

    expect(await safety.block('sam', 'sam')).toBe(true);
    expect(store.isBlocked('sam')).toBe(true);
    expect(redraws.length).toBeGreaterThan(0);

    expect(await safety.unblock('sam', 'sam')).toBe(true);
    expect(store.isBlocked('sam')).toBe(false);
  });

  it('keeps the state when the server refused', async () => {
    const { store, safety } = setup({ fail: new Set(['POST']) });
    expect(await safety.block('sam', 'sam')).toBe(false);
    expect(store.isBlocked('sam')).toBe(false);
  });

  it('learns whom the account blocked from the server once a session, and forgets it at sign-out', async () => {
    const { store, safety, calls } = setup({ listed: [{ userId: 'tom', handle: 'tom_walsh' }] });
    safety.loadBlocked();
    safety.loadBlocked();
    await new Promise((resolve) => setTimeout(resolve, 0));
    expect(calls.filter((call) => call === 'GET /safety/blocks')).toHaveLength(1);
    expect(store.isBlocked('tom')).toBe(true);
    // Already known: no second ask on the next redraw.
    safety.loadBlocked();
    expect(calls.filter((call) => call === 'GET /safety/blocks')).toHaveLength(1);

    store.resetSession();
    expect(store.isBlocked('tom')).toBe(false);
  });

  it('asks once a session even when the server failed, rather than on every redraw', async () => {
    const { store, safety, calls } = setup({ fail: new Set(['GET']) });
    safety.loadBlocked();
    await new Promise((resolve) => setTimeout(resolve, 0));
    safety.loadBlocked();
    expect(calls.filter((call) => call === 'GET /safety/blocks')).toHaveLength(1);
    expect(store.isBlocked('tom')).toBe(false);
  });

  it('drops an answer that comes after the session changed', async () => {
    const { store, safety } = setup({ listed: [{ userId: 'tom', handle: 'tom_walsh' }] });
    const pending = safety.listBlocked();
    store.state.me = { userId: 'other', handle: 'other' };
    await pending;
    expect(store.isBlocked('tom')).toBe(false);
  });
});
