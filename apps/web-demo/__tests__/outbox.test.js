// A send the server refused shows Retry; Retry queues the very envelope that
// was sealed and the outbox delivers it, whether the refusal came on the
// first attempt or while the queue was draining. A send that was never
// sealed has nothing to send again and stays failed.

import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import { createMessages } from '../src/app/services/messages.js';
import { createOutbox } from '../src/app/services/outbox.js';
import { createSend } from '../src/app/services/send.js';
import { createStore } from '../src/app/store.js';
import { textContent } from '../src/domain/content.js';
import { createSender } from '../src/features/sender.js';
import { createMemoryKv } from '../src/platform/kv.js';
import { CONVERSATION } from './support/devices.js';
import { conversation, serverMessage } from './support/messaging.js';

// Alice's app services over her harness endpoint, against a relay whose
// answers to POST /messages the test scripts: a status to refuse with, or
// nothing to store the message.
async function aliceApp() {
  const { alice, bob } = await conversation();
  const outbound = createMemoryKv('clientMessageId');
  // gates: promises a POST waits on, in order, before it is answered.
  const relay = { refusals: [], posts: [], stored: [], gates: [] };
  const authedApi = async (path, { method, body }) => {
    expect([path, method]).toEqual(['/messages', 'POST']);
    relay.posts.push(body.clientMessageId);
    const gate = relay.gates.shift();
    if (gate) await gate;
    const status = relay.refusals.shift();
    if (status) throw Object.assign(new Error(`refused with ${status}`), { status });
    const message = serverMessage(body.envelope, { clientMessageId: body.clientMessageId });
    relay.stored.push(message);
    return { message };
  };
  const store = createStore();
  store.state.me = { userId: 'u-alice', deviceId: 'd-alice', handle: 'alice' };
  const conv = {
    id: CONVERSATION,
    type: 'direct',
    createdAt: '2026-11-11T09:00:00.000Z',
    members: [{ userId: 'u-alice', handle: 'alice' }, { userId: 'u-bob', handle: 'bob' }],
    disappearingTimerSeconds: null,
    lastMessage: null,
  };
  store.state.conversations = [conv];
  const toasts = [];
  const toast = (message, kind) => toasts.push({ message, kind });
  const stack = {
    secure: alice.secure,
    trust: alice.trust,
    media: null,
    authedApi,
    idb: { get: async (name, key) => (name === 'outbound' ? outbound.get(key) : null), all: async (name) => (name === 'outbound' ? outbound.all() : []) },
    identityDb: {
      put: async (name, row) => { if (name === 'outbound') await outbound.put(row); },
      delete: async (name, key) => { if (name === 'outbound') await outbound.delete(key); },
    },
  };
  stack.sender = createSender({ secure: alice.secure, authedApi, queue: { put: (entry) => outbound.put(entry), delete: (id) => outbound.delete(id) } });
  const messages = createMessages({ store, stack });
  const send = createSend({ store, stack, messages, realtime: { stopTyping() {} }, onSent() {}, toast });
  const outbox = createOutbox({ store, stack, messages, toast });
  const own = () => store.messagesOf(CONVERSATION).filter((message) => message.senderDeviceId === 'd-alice');
  return { alice, bob, conv, relay, outbound, store, send, outbox, toasts, own };
}

async function expectDelivered(app, text) {
  await vi.waitFor(() => expect(app.own().map((message) => message._status ?? 'delivered')).toEqual(['delivered']));
  const [view] = app.own();
  expect(view.displayText).toBe(text);
  expect(view.id).toBe(app.relay.stored.at(-1).id);
  expect(view).not.toHaveProperty('_envelope');
  expect((await app.bob.secure.open(app.relay.stored.at(-1))).content.text).toBe(text);
  expect(await app.outbound.all()).toEqual([]);
}

describe('a send in flight', () => {
  beforeEach(() => vi.stubGlobal('BroadcastChannel', undefined));
  afterEach(() => {
    vi.unstubAllGlobals();
    vi.restoreAllMocks();
  });

  // Its queue entry is due again a short while after the POST went out, so
  // that a page closed meanwhile has it sent from the next one; a drain in
  // this tab meanwhile does not send it a second time.
  it('is not posted again by a drain in the same tab, however long it takes', async () => {
    const app = await aliceApp();
    let answer;
    app.relay.gates.push(new Promise((resolve) => (answer = resolve)));
    const sending = app.send.sendContent(app.conv, textContent('slow network'));
    await vi.waitFor(() => expect(app.relay.posts).toHaveLength(1));
    const [entry] = await app.outbound.all();
    const later = entry.nextRetryAt + 60_000;
    vi.spyOn(Date, 'now').mockReturnValue(later);

    await app.outbox.drain();
    expect(app.relay.posts).toHaveLength(1);
    expect(await app.outbound.all()).toHaveLength(1);

    answer();
    await sending;
    await expectDelivered(app, 'slow network');
    expect(app.relay.posts).toHaveLength(1);
  });
});

describe('retrying a refused send', () => {
  // No BroadcastChannel: this tab drains the queue on its own.
  beforeEach(() => vi.stubGlobal('BroadcastChannel', undefined));
  afterEach(() => vi.unstubAllGlobals());

  it('sends the sealed envelope again after a refusal on the first attempt', async () => {
    const app = await aliceApp();
    app.relay.refusals.push(400);
    expect(await app.send.sendContent(app.conv, textContent('refused once'))).toBeNull();
    expect(app.own().map((message) => message._status)).toEqual(['failed']);
    expect(app.toasts.at(-1)).toMatchObject({ kind: 'error' });
    expect(await app.outbound.all()).toEqual([]);

    await app.outbox.retry(CONVERSATION, app.own()[0].clientMessageId);
    await expectDelivered(app, 'refused once');
    // The same client message id both times: the server takes it as one message.
    expect(new Set(app.relay.posts).size).toBe(1);
    expect(app.relay.posts).toHaveLength(2);
  });

  it('sends the sealed envelope again after a refusal while the queue drained', async () => {
    const app = await aliceApp();
    app.relay.refusals.push(503, 400);
    expect(await app.send.sendContent(app.conv, textContent('queued, then refused'))).toBeNull();
    expect(app.own().map((message) => message._status)).toEqual(['pending']);
    expect(await app.outbound.all()).toHaveLength(1);

    await app.outbox.drain();
    expect(app.own().map((message) => message._status)).toEqual(['failed']);
    expect(await app.outbound.all()).toEqual([]);

    await app.outbox.retry(CONVERSATION, app.own()[0].clientMessageId);
    await expectDelivered(app, 'queued, then refused');
    expect(app.relay.posts).toHaveLength(3);
  });

  it('keeps a send that was never sealed failed, and says it cannot be sent again', async () => {
    const app = await aliceApp();
    // An upload that failed before anything was sealed.
    const bubble = { id: '__pending__:c-upload', clientMessageId: 'c-upload', conversationId: CONVERSATION, senderDeviceId: 'd-alice', kind: 'file', _status: 'failed' };
    app.store.putOwnMessage(CONVERSATION, 'c-upload', bubble);

    await app.outbox.retry(CONVERSATION, 'c-upload');
    expect(app.own().map((message) => message._status)).toEqual(['failed']);
    expect(app.toasts.at(-1)).toMatchObject({ kind: 'error' });
    expect(app.relay.posts).toEqual([]);
  });
});
