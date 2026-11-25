import { describe, expect, it, vi } from 'vitest';

import { createMessages } from '../src/app/services/messages.js';
import { textContent } from '../src/domain/content.js';

const deferred = () => {
  let resolve;
  const promise = new Promise((r) => (resolve = r));
  return { promise, resolve };
};

const MESSAGE_ID = '11111111-1111-4111-8111-111111111111';
const CONV_ID = '22222222-2222-4222-8222-222222222222';

function setup() {
  const raw = {
    id: MESSAGE_ID,
    conversationId: CONV_ID,
    clientMessageId: 'client-1',
    senderDeviceId: 'device-me',
    messageType: 'text',
    ciphertext: 'c0',
    nonce: 'n0',
    version: 'veil-envelope-v2',
    conversationOrder: 1,
    serverReceivedAt: new Date().toISOString(),
  };
  const list = [{ ...raw, kind: 'text', displayText: 'original body' }];
  const store = {
    state: { messagesByConv: new Map([[CONV_ID, list]]), conversations: [] },
    locateMessage: (id) => {
      const index = list.findIndex((m) => m.id === id);
      return index === -1 ? null : { convId: CONV_ID, list, index, message: list[index] };
    },
    conversation: () => null,
    isOnScreen: () => true,
    notify: () => {},
    messagesOf: () => list,
  };
  const opens = [];
  const stack = {
    secure: {
      open: () => {
        const gate = deferred();
        opens.push(gate);
        return gate.promise;
      },
      retire: async () => {},
    },
    media: {},
    identityDb: { put: async () => {}, delete: async () => {} },
  };
  return { messages: createMessages({ store, stack }), list, raw, opens };
}

describe('reingestInPlace', () => {
  it('keeps our edit when the relay echo that started first finishes last', async () => {
    const { messages, list, raw, opens } = setup();
    const edited = { ...raw, ciphertext: 'c1', nonce: 'n1', editedAt: new Date().toISOString() };

    // The echo starts first and is still opening the old stored content.
    const echo = messages.reingestInPlace(MESSAGE_ID, edited, {});
    await vi.waitFor(() => expect(opens).toHaveLength(1));
    // Our own edit is remembered and re-ingested with the content we hold.
    await messages.reingestInPlace(MESSAGE_ID, edited, { content: textContent('edited body'), editCount: 1 });
    expect(list[0].displayText).toBe('edited body');

    opens[0].resolve({ content: textContent('original body') });
    await echo;
    expect(list[0].displayText).toBe('edited body');
    expect(list[0].editCount).toBe(1);
  });

  it('shows our edit when its relay echo was applied first with the old text', async () => {
    const { messages, list, raw, opens } = setup();
    const edited = { ...raw, ciphertext: 'c1', nonce: 'n1', editedAt: new Date().toISOString() };

    // The echo carries the new ciphertext but opens the content stored
    // before the edit was remembered.
    const echo = messages.reingestInPlace(MESSAGE_ID, edited, {});
    await vi.waitFor(() => expect(opens).toHaveLength(1));
    opens[0].resolve({ content: textContent('original body') });
    await echo;
    expect(list[0].displayText).toBe('original body');

    await messages.reingestInPlace(MESSAGE_ID, edited, { content: textContent('edited body'), editCount: 1 });
    expect(list[0].displayText).toBe('edited body');
  });

  it('applies a re-ingest that nothing newer overtook', async () => {
    const { messages, list, raw, opens } = setup();
    const pending = messages.reingestInPlace(MESSAGE_ID, { ...raw, ciphertext: 'c2', nonce: 'n2' }, {});
    await vi.waitFor(() => expect(opens).toHaveLength(1));
    opens[0].resolve({ content: textContent('from the relay') });
    await pending;
    expect(list[0].displayText).toBe('from the relay');
  });
});
