// Decrypt once: every ciphertext is opened by the ratchet exactly once, its
// content kept encrypted at rest per conversation, and rendering reads only
// from that store. What was kept of a message goes once it is deleted or
// expires (contract C4), whichever path brings that news.

import { describe, expect, it, vi } from 'vitest';

import { textContent } from '../src/domain/content.js';
import { DELETED_TEXT, ingestMessage, isShown, LOCKED_LABELS, previewLabel } from '../src/domain/ingest.js';
import { CONVERSATION, NOW } from './support/devices.js';
import { contentStores, conversation, openContentStore, serverMessage } from './support/messaging.js';

const media = { subtle: null, fetchAttachment: null };
// What the app's ingest does on the endpoint's device, at its clock.
const view = (endpoint, raw, { previous = null } = {}) => ingestMessage(raw, {
  open: (message) => endpoint.secure.open(message),
  retire: (message) => endpoint.secure.retire(message),
  media,
  previous,
  now: endpoint.now,
});

describe('message content store', () => {
  it('decrypts once and renders from store after restart', async () => {
    const { alice, bob } = await conversation();
    const sent = [];
    for (const text of ['first', 'second', 'third']) {
      const clientMessageId = `web-${text}`;
      const envelope = await alice.secure.seal(CONVERSATION, textContent(text), { clientMessageId });
      const message = serverMessage(envelope, { clientMessageId });
      await alice.secure.acknowledge(message);
      sent.push(message);
    }

    const decrypt = vi.spyOn(bob.device.cipher, 'decrypt');
    const firstViews = [];
    for (const message of sent) firstViews.push(await view(bob, message));
    expect(firstViews.map((v) => v.displayText)).toEqual(['first', 'second', 'third']);
    expect(decrypt).toHaveBeenCalledTimes(3);
    // A history refresh in the same page: no message is decrypted twice.
    for (const message of sent) await view(bob, message);
    expect(decrypt).toHaveBeenCalledTimes(3);

    // A reload: new cipher, store and messaging over the same stored data.
    bob.restart();
    const reloadedDecrypt = vi.spyOn(bob.device.cipher, 'decrypt');
    const reloaded = [];
    for (const message of sent) reloaded.push(await view(bob, message));
    expect(reloadedDecrypt).not.toHaveBeenCalled();
    expect(reloaded).toEqual(firstViews);

    // The sender reads its own messages from the store as well; it could not
    // decrypt them (their message keys were single-use).
    alice.restart();
    const aliceDecrypt = vi.spyOn(alice.device.cipher, 'decrypt');
    expect((await Promise.all(sent.map((message) => view(alice, message)))).map((v) => v.displayText))
      .toEqual(['first', 'second', 'third']);
    expect(aliceDecrypt).not.toHaveBeenCalled();
  });

  it('record moved to another key fails AAD', async () => {
    const stores = contentStores();
    const store = openContentStore(stores);
    await store.put('c-1', 'm-1', { content: textContent('secret one'), nonce: 'n-1' });
    await store.put('c-1', 'm-2', { content: textContent('secret two'), nonce: 'n-2' });
    expect((await store.get('c-1', 'm-1')).content.text).toBe('secret one');

    // Copy m-1's sealed row over m-2: same conversation key, other id.
    const row = await stores.records.get('c-1/m-1');
    await stores.records.put({ ...row, key: 'c-1/m-2', id: 'm-2' });
    expect(await store.get('c-1', 'm-2')).toBeNull();

    // Or under another conversation: another key altogether.
    await store.put('c-2', 'm-9', { content: textContent('elsewhere'), nonce: 'n-9' });
    await stores.records.put({ ...row, key: 'c-2/m-1', conversationId: 'c-2' });
    expect(await store.get('c-2', 'm-1')).toBeNull();
    expect((await store.get('c-1', 'm-1')).content.text).toBe('secret one');

    // Nothing in a stored row is readable without the key.
    const serialized = JSON.stringify([...stores.records.rows.values()], (_, value) =>
      (value instanceof Uint8Array ? new TextDecoder().decode(value) : value));
    expect(serialized).not.toContain('secret');
    expect((await stores.keys.get('c-1')).key.extractable).toBe(false);
  });

  it('conversation delete destroys key', async () => {
    const stores = contentStores();
    const store = openContentStore(stores);
    await store.put('c-1', 'm-1', { content: textContent('to be shredded'), nonce: 'n-1' });
    await store.put('c-2', 'm-2', { content: textContent('kept'), nonce: 'n-2' });
    const leftover = await stores.records.get('c-1/m-1');

    await store.deleteConversation('c-1');
    expect(await stores.keys.get('c-1')).toBeNull();
    expect(await stores.records.byIndex('c-1')).toEqual([]);
    // A copy of the sealed row that survived elsewhere opens no more.
    await stores.records.put(leftover);
    expect(await store.get('c-1', 'm-1')).toBeNull();
    // A new message in the conversation gets a new key, which opens nothing
    // that was sealed under the old one.
    await store.put('c-1', 'm-3', { content: textContent('new'), nonce: 'n-3' });
    expect(await store.get('c-1', 'm-1')).toBeNull();
    expect((await store.get('c-2', 'm-2')).content.text).toBe('kept');
  });

  it('deleted history stays hidden while the relay still serves it', async () => {
    const { alice, bob } = await conversation();
    const sent = [];
    for (const text of ['before', 'deleted too']) {
      const envelope = await alice.secure.seal(CONVERSATION, textContent(text), { clientMessageId: text });
      sent.push(serverMessage(envelope, { clientMessageId: text }));
    }
    for (const message of sent) expect((await view(bob, message)).kind).toBe('text');

    await bob.secure.forgetConversation(CONVERSATION, sent.at(-1).conversationOrder);
    for (const message of sent) expect((await view(bob, message)).kind).toBe('cleared');

    // What arrives afterwards is a new history under a new key.
    const later = await alice.secure.seal(CONVERSATION, textContent('after'), { clientMessageId: 'after' });
    expect(await view(bob, serverMessage(later, { clientMessageId: 'after' }))).toMatchObject({
      kind: 'text',
      displayText: 'after',
    });
  });
});

describe('expiry and deletion', () => {
  // A frame from Alice whose authenticated payload expires at expiresAt (ms),
  // as the relay serves it with relayedExpiresAt (ISO) on the envelope.
  async function fromAlice(alice, text, { expiresAt = null, relayedExpiresAt = null } = {}) {
    await alice.secure.prepare(CONVERSATION);
    const envelope = await alice.device.cipher.encrypt({
      conversationId: CONVERSATION,
      senderDeviceId: alice.deviceId,
      recipientUserId: 'u-bob',
      payload: { body: text, kind: 'text', expiresAt },
    });
    return { ...serverMessage(envelope), expiresAt: relayedExpiresAt };
  }

  const rowOf = (endpoint, message) => endpoint.stores.records.get(`${CONVERSATION}/${message.id}`);
  const retiredRow = (message) => ({ key: `${CONVERSATION}/${message.id}`, conversationId: CONVERSATION, id: message.id, retired: true });

  it('an expired peer message leaves no row in the content store and never previews', async () => {
    const { alice, bob } = await conversation();
    const message = await fromAlice(alice, 'self-destructing secret', { expiresAt: NOW - 1 });
    const decrypt = vi.spyOn(bob.device.cipher, 'decrypt');

    const expired = await view(bob, message);
    expect(expired).toMatchObject({ kind: 'expired', displayText: '', media: null });
    // Its message key is spent all the same.
    expect(decrypt).toHaveBeenCalledTimes(1);
    expect(isShown(expired, bob.now)).toBe(false);
    expect(previewLabel(expired, bob.now)).toBe('');
    expect(await rowOf(bob, message)).toEqual(retiredRow(message));

    // A reload brings nothing back, and nothing is decrypted again.
    bob.restart();
    const reloadedDecrypt = vi.spyOn(bob.device.cipher, 'decrypt');
    expect(await bob.contentStore.get(CONVERSATION, message.id)).toEqual({ retired: true });
    expect(await view(bob, message)).toMatchObject({ kind: 'expired', displayText: '' });
    expect(reloadedDecrypt).not.toHaveBeenCalled();
  });

  it('a stored message is retired when its expiry passes, loaded or not', async () => {
    const { alice, bob } = await conversation();
    const innerExpiry = NOW + 60_000;
    const relayedExpiry = NOW + 30_000;
    const inner = await fromAlice(alice, 'gone in a minute', { expiresAt: innerExpiry });
    const relayed = await fromAlice(alice, 'the relay says sooner', {
      expiresAt: innerExpiry,
      relayedExpiresAt: new Date(relayedExpiry).toISOString(),
    });
    const shown = [await view(bob, inner), await view(bob, relayed)];
    expect(shown.map((v) => [v.displayText, v.expiresAtMs])).toEqual([
      ['gone in a minute', innerExpiry],
      ['the relay says sooner', relayedExpiry],
    ]);
    expect([(await rowOf(bob, inner)).expiresAt, (await rowOf(bob, relayed)).expiresAt]).toEqual([innerExpiry, relayedExpiry]);

    bob.now = relayedExpiry;
    // Between sweeps a view past its expiry already shows nothing.
    expect(isShown(shown[1], bob.now)).toBe(false);
    expect(previewLabel(shown[1], bob.now)).toBe('');
    await bob.secure.retireExpired();
    expect(await rowOf(bob, relayed)).toEqual(retiredRow(relayed));
    expect((await bob.contentStore.get(CONVERSATION, inner.id)).content.text).toBe('gone in a minute');

    bob.now = innerExpiry;
    await bob.secure.retireExpired();
    expect(await rowOf(bob, inner)).toEqual(retiredRow(inner));
    // The views go the same way when they are next ingested.
    for (const [index, message] of [inner, relayed].entries()) {
      expect(await view(bob, message, { previous: shown[index] })).toMatchObject({ kind: 'expired', displayText: '' });
    }
  });

  it('own content expires with the expiry the relay set on it', async () => {
    const { alice } = await conversation();
    const envelope = await alice.secure.seal(CONVERSATION, textContent('timer is on'), { clientMessageId: 'web-t' });
    const relayedExpiry = NOW + 30_000;
    const message = {
      ...serverMessage(envelope, { clientMessageId: 'web-t' }),
      expiresAt: new Date(relayedExpiry).toISOString(),
    };
    await alice.secure.acknowledge(message);
    expect((await rowOf(alice, message)).expiresAt).toBe(relayedExpiry);

    alice.now = relayedExpiry;
    await alice.secure.retireExpired();
    expect(await rowOf(alice, message)).toEqual(retiredRow(message));
    expect((await view(alice, message)).kind).toBe('expired');
  });

  it('a deletedAt tombstone fetched through polling removes the stored row', async () => {
    const { alice, bob } = await conversation();
    const envelope = await alice.secure.seal(CONVERSATION, textContent('regrettable'), { clientMessageId: 'web-r' });
    const message = serverMessage(envelope, { clientMessageId: 'web-r' });
    await alice.secure.acknowledge(message);
    const shown = { alice: await view(alice, message), bob: await view(bob, message) };
    expect([shown.alice.displayText, shown.bob.displayText]).toEqual(['regrettable', 'regrettable']);

    // What a history refresh returns once the sender has deleted it.
    const tombstone = { ...message, deletedAt: '2026-11-11T09:05:00.000Z' };
    for (const endpoint of [alice, bob]) {
      expect(await view(endpoint, tombstone, { previous: shown[endpoint.handle] }))
        .toMatchObject({ kind: 'deleted', displayText: DELETED_TEXT, media: null });
      expect(await rowOf(endpoint, message)).toEqual(retiredRow(message));
      // A relay that serves the original again gets it hidden, not opened.
      endpoint.restart();
      const decrypt = vi.spyOn(endpoint.device.cipher, 'decrypt');
      expect(await view(endpoint, message)).toMatchObject({ kind: 'expired', displayText: '' });
      expect(decrypt).not.toHaveBeenCalled();
    }
  });

  it('a retired record stays retired whatever is written to it later', async () => {
    const stores = contentStores();
    const store = openContentStore(stores);
    await store.put('c-1', 'm-1', { content: textContent('first'), nonce: 'n-1' }, { expiresAt: NOW + 10 });
    // A rewrite (an edit) cannot push the expiry back.
    await store.put('c-1', 'm-1', { content: textContent('edited'), nonce: 'n-2' }, { expiresAt: NOW + 99 });
    expect((await stores.records.get('c-1/m-1')).expiresAt).toBe(NOW + 10);

    await store.retireExpired(NOW + 10);
    await store.put('c-1', 'm-1', { content: textContent('back from the dead'), nonce: 'n-3' });
    expect(await store.get('c-1', 'm-1')).toEqual({ retired: true });
    expect(await stores.records.get('c-1/m-1')).toEqual({ key: 'c-1/m-1', conversationId: 'c-1', id: 'm-1', retired: true });
  });

  it('a retire that lands while a put is sealing is not overwritten', async () => {
    const stores = contentStores();
    const store = openContentStore(stores);
    // A decryption keeps its content while an ingest of the tombstone
    // retires the same message: the put has read the row and is still sealing.
    const putting = store.put('c-1', 'm-1', { content: textContent('deleted meanwhile'), nonce: 'n-1' });
    const retiring = store.retire('c-1', 'm-1');
    await Promise.all([putting, retiring]);
    expect(await store.get('c-1', 'm-1')).toEqual({ retired: true });
    expect(await stores.records.get('c-1/m-1')).toEqual({ key: 'c-1/m-1', conversationId: 'c-1', id: 'm-1', retired: true });
  });
});

// The relay names each envelope's id and sender. Content is filed under the
// id, so every record also names who wrote it, and nothing the relay
// relabels or re-files shows one party's words as the other's or replaces
// what was kept.
describe('authorship of stored content', () => {
  const tombstoned = (raw) => ({ ...raw, deletedAt: '2026-11-11T09:05:00.000Z' });

  // Alice's message, sent and acknowledged; Bob's, sealed but not yet
  // delivered to her (the relay may withhold it).
  async function exchange() {
    const { alice, bob } = await conversation();
    const sent = await alice.secure.seal(CONVERSATION, textContent('I agree to pay 1000'), { clientMessageId: 'a-1' });
    const fromAlice = serverMessage(sent, { clientMessageId: 'a-1' });
    await alice.secure.acknowledge(fromAlice);
    expect((await view(bob, fromAlice)).displayText).toBe('I agree to pay 1000');
    const reply = await bob.secure.seal(CONVERSATION, textContent('words bob wrote'), { clientMessageId: 'b-1' });
    const fromBob = serverMessage(reply, { clientMessageId: 'b-1' });
    await bob.secure.acknowledge(fromBob);
    return { alice, bob, fromAlice, fromBob };
  }

  // What Alice's history shows for a message after a reload.
  async function afterReload(alice, message) {
    alice.restart();
    return view(alice, message);
  }

  // Another tab files content under `id` while this one opens a frame the
  // relay served under it: this tab's first read of the id finds nothing.
  function racingTab(endpoint, id) {
    const get = endpoint.contentStore.get.bind(endpoint.contentStore);
    let raced = false;
    vi.spyOn(endpoint.contentStore, 'get').mockImplementation(async (conversationId, recordId) => {
      if (recordId === id && !raced) {
        raced = true;
        return null;
      }
      return get(conversationId, recordId);
    });
  }

  it('our own message relabelled as the peer\'s, nonce cleared, stays locked', async () => {
    const { alice, fromAlice } = await exchange();
    const genuine = await view(alice, fromAlice);
    expect(genuine).toMatchObject({ senderDeviceId: 'd-alice', displayText: 'I agree to pay 1000' });

    // Whatever ciphertext comes with it.
    for (const ciphertext of [fromAlice.ciphertext, 'AAAA']) {
      const relabelled = { ...fromAlice, senderDeviceId: 'd-bob', nonce: null, ciphertext };
      expect(await view(alice, relabelled, { previous: genuine })).toMatchObject({ kind: 'locked', senderDeviceId: 'd-bob' });
    }
    expect(await afterReload(alice, fromAlice)).toMatchObject({ kind: 'text', displayText: 'I agree to pay 1000' });
  });

  it('the peer\'s message relabelled as ours is not shown as ours', async () => {
    const { alice, fromBob } = await exchange();
    const relabelled = { ...fromBob, senderDeviceId: 'd-alice' };
    // Before Alice has opened it, and after.
    expect(await view(alice, relabelled)).toMatchObject({ kind: 'locked', displayText: LOCKED_LABELS['own-missing'] });
    const genuine = await view(alice, fromBob);
    expect(genuine).toMatchObject({ senderDeviceId: 'd-bob', displayText: 'words bob wrote' });
    expect(await view(alice, relabelled, { previous: genuine })).toMatchObject({ kind: 'locked', senderDeviceId: 'd-alice' });
  });

  it('a peer frame filed under our message id replaces nothing and still opens under its own', async () => {
    const { alice, fromAlice, fromBob } = await exchange();
    const refiled = { ...fromBob, id: fromAlice.id, conversationOrder: fromAlice.conversationOrder };
    const decrypt = vi.spyOn(alice.device.cipher, 'decrypt');
    expect(await view(alice, refiled)).toMatchObject({ kind: 'locked', senderDeviceId: 'd-bob' });
    expect(decrypt).not.toHaveBeenCalled();

    expect(await afterReload(alice, fromAlice)).toMatchObject({ senderDeviceId: 'd-alice', displayText: 'I agree to pay 1000' });
    expect(await view(alice, fromBob)).toMatchObject({ senderDeviceId: 'd-bob', displayText: 'words bob wrote' });
  });

  it('a peer frame already opened, served again under our message id, does not show our words', async () => {
    const { alice, fromAlice, fromBob } = await exchange();
    expect((await view(alice, fromBob)).displayText).toBe('words bob wrote');
    expect(await view(alice, { ...fromBob, id: fromAlice.id })).toMatchObject({ kind: 'locked', senderDeviceId: 'd-bob' });
    expect(await afterReload(alice, fromAlice)).toMatchObject({ displayText: 'I agree to pay 1000' });
  });

  it('a decryption that would overwrite another author\'s record does not commit', async () => {
    const { alice, fromAlice, fromBob } = await exchange();
    racingTab(alice, fromAlice.id);
    expect(await view(alice, { ...fromBob, id: fromAlice.id })).toMatchObject({ kind: 'locked' });
    expect(await afterReload(alice, fromAlice)).toMatchObject({ displayText: 'I agree to pay 1000' });
    // Its message key was not spent.
    expect(await view(alice, fromBob)).toMatchObject({ senderDeviceId: 'd-bob', displayText: 'words bob wrote' });
  });

  it('a replayed frame reads back only what was kept of that very frame', async () => {
    const { alice, fromAlice, fromBob } = await exchange();
    expect((await view(alice, fromBob)).displayText).toBe('words bob wrote');
    racingTab(alice, fromAlice.id);
    expect(await view(alice, { ...fromBob, id: fromAlice.id })).toMatchObject({ kind: 'locked', senderDeviceId: 'd-bob' });
  });

  it('a server id cannot name a local record', async () => {
    const { alice, bob } = await conversation();
    // Alice's send is pending under its client id when the relay files a
    // frame of Bob's, then a tombstone, there.
    const sent = await alice.secure.seal(CONVERSATION, textContent('pending words'), { clientMessageId: 'a-9' });
    const reply = await bob.secure.seal(CONVERSATION, textContent('text bob wrote'), { clientMessageId: 'b-9' });
    const fromBob = serverMessage(reply, { clientMessageId: 'b-9' });
    expect(await view(alice, { ...fromBob, id: 'client:a-9' })).toMatchObject({ kind: 'locked' });
    expect(await view(alice, tombstoned({ ...fromBob, id: 'client:a-9' }))).toMatchObject({ kind: 'deleted' });
    const fromAlice = serverMessage(sent, { clientMessageId: 'a-9' });
    await alice.secure.acknowledge(fromAlice);
    expect(await view(alice, fromAlice)).toMatchObject({ senderDeviceId: 'd-alice', displayText: 'pending words' });
    expect(await view(alice, fromBob)).toMatchObject({ displayText: 'text bob wrote' });

    // Nor the marker of deleted history, which stays hidden.
    await alice.secure.forgetConversation(CONVERSATION, fromAlice.conversationOrder);
    const later = serverMessage(await bob.secure.seal(CONVERSATION, textContent('later'), { clientMessageId: 'b-10' }));
    await view(alice, { ...later, id: 'history-cleared' });
    await view(alice, tombstoned({ ...later, id: 'history-cleared' }));
    for (const message of [fromAlice, fromBob]) expect((await view(alice, message)).kind).toBe('cleared');
    expect(await view(alice, later)).toMatchObject({ displayText: 'later' });
  });

  it('the store keeps a record from being rewritten by another author', async () => {
    const store = openContentStore(contentStores());
    const value = (text, author) => ({ content: textContent(text), nonce: null, author });
    expect(await store.put('c-1', 'm-1', value('mine', 'd-alice'))).toBe(true);
    expect(await store.put('c-1', 'm-1', value('theirs', 'd-bob'))).toBe(false);
    expect(await store.put('c-1', 'm-1', value('mine, edited', 'd-alice'))).toBe(true);
    expect((await store.get('c-1', 'm-1')).content.text).toBe('mine, edited');

    // A move onto another author's record leaves both where they are.
    await store.put('c-1', 'client:x', value('pending', 'd-alice'));
    await store.put('c-1', 'm-2', value('theirs', 'd-bob'));
    await store.move('c-1', 'client:x', 'm-2');
    expect((await store.get('c-1', 'm-2')).content.text).toBe('theirs');
    expect((await store.get('c-1', 'client:x')).content.text).toBe('pending');
  });
});
