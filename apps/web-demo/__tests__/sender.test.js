// What a send puts beside and inside the ciphertext: a client message id
// that says nothing about the message, and, under a disappearing timer, the
// expiry sealed into the payload, so a relay that drops or extends the
// outer expiresAt cannot keep the message around (contract C4).

import { describe, expect, it, vi } from 'vitest';

import { disappearingExpiry, mediaContent, payloadFromContent, reactionContent, textContent } from '../src/domain/content.js';
import { createSender, newClientMessageId } from '../src/features/sender.js';
import { CONVERSATION } from './support/devices.js';
import { conversation, serverMessage } from './support/messaging.js';

const UUID_V4 = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
// SendMessageDto.clientMessageId
const SERVER_CLIENT_ID = /^[a-zA-Z0-9._:-]{8,80}$/;
const MINUTE_MS = 60 * 1000;

describe('client message ids', () => {
  it('are random UUIDs, with no clock and no content kind in them', () => {
    const ids = Array.from({ length: 50 }, () => newClientMessageId());
    for (const id of ids) {
      expect(id).toMatch(UUID_V4);
      expect(id).toMatch(SERVER_CLIENT_ID);
    }
    expect(new Set(ids).size).toBe(ids.length);
  });
});

describe('the sealed expiry', () => {
  it('is in the payload of every kind a sender seals', () => {
    const expiresAt = Date.parse('2026-11-12T09:01:00Z');
    const pointer = { id: '3b241101-e2bb-4255-8caf-4136c566a962', ck: 'k', n: 'n', d: 'd', ct: 'image/png', sz: 1, alg: 'a' };
    for (const content of [
      textContent('hi'),
      textContent('re', 'm-1'),
      reactionContent({ target: 'm-1', emoji: '👍', op: 'add' }),
      mediaContent('image', pointer),
    ]) {
      expect(payloadFromContent({ ...content, expiresAt }).expiresAt).toBe(expiresAt);
      expect(payloadFromContent(content).expiresAt).toBeNull();
    }
  });

  it('follows the conversation timer', () => {
    const now = Date.parse('2026-11-12T09:00:00Z');
    expect(disappearingExpiry(60, now)).toBe(now + MINUTE_MS);
    for (const timer of [null, undefined, 0, -5, 1.5]) expect(disappearingExpiry(timer, now)).toBeNull();
  });

  // The relay stores the messages with no outer expiresAt at all.
  it('retires a message and a reaction on both sides when the relay drops the outer expiry', async () => {
    const { alice, bob } = await conversation();
    const server = { stored: [] };
    const authedApi = vi.fn(async (path, { body }) => {
      const message = serverMessage(body.envelope, { clientMessageId: body.clientMessageId });
      server.stored.push(message);
      return { message };
    });
    const queue = { put: vi.fn() };
    const aliceSender = createSender({ secure: alice.secure, authedApi, queue });
    const bobSender = createSender({ secure: bob.secure, authedApi, queue });

    const expiresAt = disappearingExpiry(60, alice.now);
    const clientMessageId = newClientMessageId();
    const envelope = await aliceSender.seal(CONVERSATION, { ...textContent('disappearing hello'), expiresAt }, { clientMessageId });
    expect(envelope.expiresAt).toBeUndefined();
    const { message } = await aliceSender.deliver({ conversationId: CONVERSATION, clientMessageId, envelope });
    expect(message.expiresAt).toBeNull();
    const opened = await bob.secure.open(message);
    expect(opened.content).toMatchObject({ text: 'disappearing hello', expiresAt });

    const { message: reaction } = await bobSender.react({
      conversationId: CONVERSATION,
      clientMessageId: newClientMessageId(),
      target: message.id,
      emoji: '👍',
      current: null,
      expiresAt,
    });
    expect((await alice.secure.open(reaction)).content).toMatchObject({ kind: 'reaction', expiresAt });

    for (const endpoint of [alice, bob]) {
      endpoint.now = expiresAt;
      await endpoint.secure.retireExpired();
      for (const sent of [message, reaction]) expect(await endpoint.secure.open(sent)).toEqual({ failure: 'retired' });
    }
  });
});
