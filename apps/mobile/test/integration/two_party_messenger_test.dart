import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/core/crypto/lib_crypto_adapter.dart';
import 'package:veil_mobile/src/features/conversations/data/conversation_models.dart';

import '../support/async_wait.dart';
import '../support/fake_relay.dart';
import '../support/messenger_party.dart';

// Two real controllers, each with its own LibCryptoAdapter, identity and
// encrypted Drift cache, talking through the fake relay. Every regression
// here was invisible to the idempotent MockCryptoAdapter: ratchet message
// keys are single-use and a sender cannot open its own frames.

const conv = 'conv-ab';

void main() {
  late FakeRelay relay;
  late MessengerParty alice;
  late MessengerParty bob;

  setUp(() async {
    relay = FakeRelay();
    alice = await MessengerParty.join(relay, handle: 'alice', userId: 'user-alice', deviceId: 'dev-alice');
    bob = await MessengerParty.join(relay, handle: 'bob', userId: 'user-bob', deviceId: 'dev-bob');
    relay.addDirect(conv, 'alice', 'bob');
    await alice.signIn();
    await bob.signIn();
  });

  tearDown(() async {
    await alice.dispose();
    await bob.dispose();
  });

  Future<void> deliver(
    MessengerParty from,
    MessengerParty to,
    String body, {
    String conversationId = conv,
  }) async {
    await from.controller.sendText(conversationId: conversationId, body: body);
    await waitFor(
      () => from.controller.pendingCountFor(conversationId) == 0,
      reason: '"$body" was not acked',
    );
    await waitFor(
      () async => (await to.bodies(conversationId)).contains(body),
      reason: '"$body" is not readable by ${to.device.handle}',
    );
  }

  test('refresh between sends keeps the session', () async {
    await deliver(alice, bob, 'm1');
    await alice.controller.refreshConversations();
    await deliver(alice, bob, 'm2');

    expect(await bob.bodies(conv), ['m1', 'm2']);
    expect(alice.crypto.counts.bootstrap, 1);
  });

  test('receiving a message between sends keeps the session', () async {
    await deliver(alice, bob, 'm1');
    await deliver(bob, alice, 'r1');
    // Lets the conversation.sync hint the reply triggers refresh alice's list.
    await settle();
    await deliver(alice, bob, 'm2');

    expect(await alice.bodies(conv), ['m1', 'r1', 'm2']);
    expect(await bob.bodies(conv), ['m1', 'r1', 'm2']);
    expect(alice.crypto.counts.bootstrap + bob.crypto.counts.bootstrap, 1);
  });

  test('app resume between sends keeps the session', () async {
    await deliver(alice, bob, 'm1');
    await alice.controller.handleAppResumed();
    await settle();
    await deliver(alice, bob, 'm2');

    expect(await bob.bodies(conv), ['m1', 'm2']);
  });

  test('token refresh keeps history and does not refetch conversations', () async {
    await deliver(alice, bob, 'kept');
    // Let the sync hint that delivery raised finish before taking a baseline.
    await settle();
    final message = bob.controller.messagesFor(conv).single;
    final shown = bob.controller.decryptMessage(message);
    final conversationFetches = bob.api.conversationFetches;
    final connects = bob.realtime.connectCount;
    bob.crypto.counts.reset();

    await bob.refreshToken();
    await settle();

    expect(bob.realtime.connectCount, connects + 1);
    expect(bob.realtime.lastAccessToken, bob.session().accessToken);
    expect(bob.api.conversationFetches, conversationFetches);
    expect(identical(bob.controller.decryptMessage(message), shown), isTrue);
    expect(await bob.bodies(conv), ['kept']);
    expect(bob.crypto.counts.decrypt, 0);

    await deliver(alice, bob, 'after refresh');
    expect(await bob.bodies(conv), ['kept', 'after refresh']);
  });

  test('twenty alternating messages all decrypt', () async {
    final expected = <String>[];
    for (var round = 0; round < 10; round++) {
      await deliver(alice, bob, 'a$round');
      expected.add('a$round');
      await deliver(bob, alice, 'b$round');
      expected.add('b$round');
    }

    expect(await alice.bodies(conv), expected);
    expect(await bob.bodies(conv), expected);
  });

  test('own sent message renders after controller restart over the same database', () async {
    await deliver(alice, bob, 'hello from alice');
    expect(await alice.bodies(conv), ['hello from alice']);

    await alice.restart();
    await settle();

    expect(await alice.bodies(conv), ['hello from alice']);
    expect(alice.crypto.counts.decrypt, 0);
    await deliver(alice, bob, 'ratchet survived');
    expect(await bob.bodies(conv), ['hello from alice', 'ratchet survived']);
  });

  test('received body survives restart with zero crypto calls', () async {
    await deliver(alice, bob, 'remember me');

    await bob.restart();
    await settle();

    expect(await bob.bodies(conv), ['remember me']);
    expect(bob.crypto.counts.decrypt, 0);
  });

  test('group key change leaves direct bodies intact', () async {
    relay.addGroup('grp', ['alice', 'bob']);
    await alice.controller.refreshConversations();
    await bob.controller.refreshConversations();
    await deliver(alice, bob, 'direct before');
    alice.crypto.counts.reset();
    bob.crypto.counts.reset();

    // Alice's first group send creates and distributes her chain key; bob
    // picks it up when the frame arrives. Both fire a group key event.
    await deliver(alice, bob, 'group hello', conversationId: 'grp');

    expect(await bob.bodies('grp'), ['group hello']);
    expect(await alice.bodies(conv), ['direct before']);
    expect(await bob.bodies(conv), ['direct before']);
    expect(alice.crypto.counts.decrypt + bob.crypto.counts.decrypt, 0);
  });

  test('oldest of 700 messages readable after cache eviction', () async {
    await deliver(alice, bob, 'm0');
    final bobBundle = KeyBundle(
      userId: bob.device.userId,
      deviceId: bob.device.deviceId,
      handle: bob.device.handle,
      identityPublicKey: bob.device.identity.identityPublicKey,
      signedPrekeyBundle: bob.device.identity.signedPrekeyBundle,
    );
    // Sealed with alice's live ratchet and relayed in order, without paying
    // for 699 round trips through her outbox.
    for (var index = 1; index < 700; index++) {
      final envelope = await alice.crypto.messaging.encryptMessage(
        conversationId: conv,
        senderDeviceId: alice.device.deviceId,
        recipientUserId: bob.device.userId,
        body: 'm$index',
        messageKind: MessageKind.text,
        recipientBundle: bobBundle,
      );
      relay.inject(
        senderHandle: 'alice',
        conversationId: conv,
        envelope: alice.crypto.envelopeCodec.encodeApiEnvelope(envelope),
      );
    }
    bob.crypto.counts.reset();

    await bob.controller.loadConversationMessages(conv);
    await waitFor(
      () => bob.crypto.counts.decrypt == 699,
      timeout: const Duration(seconds: 20),
      reason: 'history was not ingested',
    );
    final messages = bob.controller.messagesFor(conv);

    expect(messages, hasLength(700));
    expect((await bob.controller.decryptMessage(messages.first)).body, 'm0');
    expect((await bob.controller.decryptMessage(messages.last)).body, 'm699');
    expect(bob.crypto.counts.decrypt, 699);
  });

  test('expiry removes content row at inner time when outer expiresAt is removed', () async {
    relay.stripOuterExpiresAt = true;
    await alice.controller.sendText(
      conversationId: conv,
      body: 'self-destruct',
      disappearAfter: const Duration(seconds: 1),
    );
    await waitFor(() async => (await bob.bodies(conv)).contains('self-destruct'));
    final message = bob.controller.messagesFor(conv).single;
    expect(relay.conversations[conv]!.messages.single['expiresAt'], isNull);
    expect(bob.controller.messagesFor(conv).single.expiresAt, isNotNull);
    expect(await bob.cache.get(message.id), isNotNull);

    await waitFor(
      () async =>
          bob.controller.messagesFor(conv).isEmpty && await bob.cache.get(message.id) == null,
      reason: 'message outlived its authenticated expiry',
    );
  });

  test('search returns hits without calling decrypt', () async {
    await deliver(alice, bob, 'needle in the haystack');
    await deliver(alice, bob, 'unrelated chatter');
    await settle();
    alice.crypto.counts.reset();
    bob.crypto.counts.reset();

    final needle = bob.controller.messagesFor(conv).first;
    expect(await bob.controller.searchLoadedMessageIds(conv, query: 'NEEDLE'), [needle.id]);
    expect(
      await alice.controller.searchLoadedMessageIds(conv, query: 'needle'),
      [alice.controller.messagesFor(conv).first.id],
    );
    final archive = await bob.controller.searchMessageArchive(
      query: const MessageSearchQuery(query: 'needle'),
    );
    expect(archive.items.single.messageId, needle.id);
    expect(archive.items.single.bodySnippet, contains('needle'));
    expect(alice.crypto.counts.decrypt + bob.crypto.counts.decrypt, 0);
  });

  test('leaving the chat stops auto read receipts and restores notifications', () async {
    bob.controller.setActiveConversation(conv);
    await deliver(alice, bob, 'seen');
    await waitFor(() => bob.api.markReadCalls.length == 1);
    expect(bob.notifications.shownForConversations, isEmpty);

    bob.controller.setActiveConversation(null);
    await deliver(alice, bob, 'unseen');
    await settle();

    expect(bob.api.markReadCalls, hasLength(1));
    expect(bob.notifications.shownForConversations, [conv]);
  });

  test('key bundle fetched at most once per session setup', () async {
    for (var index = 0; index < 3; index++) {
      await deliver(alice, bob, 'a$index');
    }
    await alice.controller.refreshConversations();
    await deliver(bob, alice, 'b0');
    await alice.controller.handleAppResumed();
    await settle();
    await deliver(alice, bob, 'a3');

    expect(alice.api.keyBundleFetches, {'bob': 1});
    // The responder looks alice up once, when her first frame sets up its
    // session, so it has her identity key for safety numbers.
    expect(bob.api.keyBundleFetches, {'alice': 1});
    final bobView = bob.controller.conversations.firstWhere((item) => item.id == conv);
    expect(bobView.recipientBundle.identityPublicKey, alice.device.identity.identityPublicKey);
  });

  test('identity key change for same device does not rebootstrap and flags preview', () async {
    await deliver(alice, bob, 'before swap');
    final impostor = await LibCryptoAdapter().identity.generateDeviceIdentity(bob.device.deviceId);
    relay.bundleOverrides['bob'] = {
      ...bob.device.bundleJson,
      'identityPublicKey': impostor.identityPublicKey,
      'signedPrekeyBundle': impostor.signedPrekeyBundle,
    };

    final served = await alice.controller.fetchPeerKeyBundle('bob');

    expect(served.identityPublicKey, impostor.identityPublicKey);
    final preview = alice.controller.conversations.firstWhere((item) => item.id == conv);
    expect(preview.identityMismatchPending, isTrue);
    expect(preview.sessionState!.remoteIdentityPublicKey, bob.device.identity.identityPublicKey);
    expect(alice.crypto.counts.bootstrap, 1);
    await waitFor(() async => (await alice.cache.readConversations())
        .firstWhere((item) => item.id == conv)
        .identityMismatchPending);

    await deliver(alice, bob, 'after swap');
    expect(await bob.bodies(conv), ['before swap', 'after swap']);
    expect(alice.crypto.counts.bootstrap, 1);
  });

  test('attachment upload carries ciphertext the peer can decrypt', () async {
    await deliver(alice, bob, 'file incoming');

    await alice.controller.sendAttachmentPlaceholder(conv, filename: 'brief.pdf');
    await waitFor(() => alice.controller.pendingCountFor(conv) == 0, reason: 'attachment not sent');
    await waitFor(() => bob.controller.messagesFor(conv).length == 2);
    final received = await bob.controller.decryptMessage(bob.controller.messagesFor(conv).last);

    expect(received.messageKind, MessageKind.file);
    final reference = received.attachment!;
    final uploaded = relay.uploadedBlobs[reference.attachmentId]!;
    expect(reference.sizeBytes, uploaded.length);
    final plaintext = await bob.crypto.messaging.decryptAttachment(
      reference: reference,
      ciphertext: uploaded,
      localIdentityPrivateRef: bob.device.identity.identityPrivateKeyRef,
    );
    expect(plaintext, hasLength(2048));
    final sent = await alice.controller.decryptMessage(alice.controller.messagesFor(conv).last);
    expect(sent.attachment!.attachmentId, reference.attachmentId);
  });
}
